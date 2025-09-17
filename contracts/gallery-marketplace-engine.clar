;; Gallery Marketplace Engine Smart Contract
;; Facilitates digital art sales with automated pricing and bidding mechanisms,
;; processes artist royalty payments on secondary sales, manages gallery curation
;; and exhibition spaces, handles collector portfolio management, and provides
;; transparent sales analytics with market insights.

;; =============================================================================
;; CONSTANTS
;; =============================================================================

(define-constant contract-owner tx-sender)
(define-constant err-owner-only (err u200))
(define-constant err-not-found (err u201))
(define-constant err-already-exists (err u202))
(define-constant err-unauthorized (err u203))
(define-constant err-invalid-input (err u204))
(define-constant err-insufficient-funds (err u205))
(define-constant err-artwork-not-for-sale (err u206))
(define-constant err-invalid-bid (err u207))
(define-constant err-auction-ended (err u208))
(define-constant err-auction-active (err u209))
(define-constant err-gallery-full (err u210))

;; Sale status constants
(define-constant sale-status-not-for-sale u0)
(define-constant sale-status-fixed-price u1)
(define-constant sale-status-auction u2)
(define-constant sale-status-sold u3)

;; Gallery type constants
(define-constant gallery-type-featured u1)
(define-constant gallery-type-curated u2)
(define-constant gallery-type-community u3)
(define-constant gallery-type-private u4)

;; =============================================================================
;; DATA VARIABLES
;; =============================================================================

(define-data-var next-listing-id uint u1)
(define-data-var next-gallery-id uint u1)
(define-data-var next-auction-id uint u1)
(define-data-var platform-fee-percentage uint u250) ;; 2.5%
(define-data-var total-sales-volume uint u0)
(define-data-var total-transactions uint u0)
(define-data-var min-auction-duration uint u144) ;; ~1 day in blocks
(define-data-var max-gallery-artworks uint u100)

;; =============================================================================
;; DATA MAPS
;; =============================================================================

;; Artwork listings for sale
(define-map artwork-listings
  { listing-id: uint }
  {
    artwork-id: uint,
    seller: principal,
    price: uint,
    sale-status: uint,
    listing-timestamp: uint,
    expiry-timestamp: uint,
    royalty-recipient: principal,
    royalty-percentage: uint,
    description: (string-utf8 512)
  }
)

;; Auction details for artworks
(define-map artwork-auctions
  { auction-id: uint }
  {
    listing-id: uint,
    artwork-id: uint,
    seller: principal,
    starting-price: uint,
    current-highest-bid: uint,
    highest-bidder: (optional principal),
    auction-end-block: uint,
    total-bids: uint,
    reserve-price: uint,
    is-active: bool
  }
)

;; Bid history tracking
(define-map bid-history
  { auction-id: uint, bid-sequence: uint }
  {
    bidder: principal,
    bid-amount: uint,
    bid-timestamp: uint,
    is-winning-bid: bool
  }
)

;; Gallery management
(define-map galleries
  { gallery-id: uint }
  {
    owner: principal,
    name: (string-utf8 256),
    description: (string-utf8 1024),
    gallery-type: uint,
    creation-timestamp: uint,
    artwork-count: uint,
    is-public: bool,
    featured-artwork: (optional uint),
    metadata-hash: (string-ascii 64)
  }
)

;; Gallery artwork associations
(define-map gallery-artworks
  { gallery-id: uint, artwork-slot: uint }
  {
    artwork-id: uint,
    added-timestamp: uint,
    display-order: uint,
    curator-notes: (string-utf8 256)
  }
)

;; Collector portfolios
(define-map collector-portfolios
  { collector-address: principal }
  {
    total-artworks: uint,
    total-value: uint,
    first-purchase-timestamp: uint,
    last-activity-timestamp: uint,
    favorite-artist: (optional principal),
    portfolio-hash: (string-ascii 64)
  }
)

;; Sales analytics and metrics
(define-map sales-metrics
  { period-start: uint, period-end: uint }
  {
    total-volume: uint,
    total-transactions: uint,
    average-price: uint,
    unique-buyers: uint,
    unique-sellers: uint,
    top-artwork-id: uint
  }
)

;; Artist royalty tracking
(define-map royalty-payments
  { artist: principal, artwork-id: uint }
  {
    total-royalties-earned: uint,
    last-payment-timestamp: uint,
    total-secondary-sales: uint,
    average-royalty-amount: uint
  }
)

;; =============================================================================
;; PUBLIC FUNCTIONS
;; =============================================================================

;; List artwork for sale at fixed price
(define-public (list-artwork-for-sale 
  (artwork-id uint)
  (price uint)
  (expiry-blocks uint)
  (royalty-recipient principal)
  (royalty-percentage uint)
  (description (string-utf8 512))
)
  (let (
    (listing-id (var-get next-listing-id))
    (seller tx-sender)
    (expiry-timestamp (+ burn-block-height expiry-blocks))
  )
    (asserts! (> price u0) err-invalid-input)
    (asserts! (<= royalty-percentage u1000) err-invalid-input) ;; Max 10% royalty
    (asserts! (> expiry-blocks u0) err-invalid-input)
    
    (map-set artwork-listings
      { listing-id: listing-id }
      {
        artwork-id: artwork-id,
        seller: seller,
        price: price,
        sale-status: sale-status-fixed-price,
        listing-timestamp: burn-block-height,
        expiry-timestamp: expiry-timestamp,
        royalty-recipient: royalty-recipient,
        royalty-percentage: royalty-percentage,
        description: description
      }
    )
    
    (var-set next-listing-id (+ listing-id u1))
    
    (print { event: "artwork-listed", listing-id: listing-id, artwork-id: artwork-id, price: price })
    (ok listing-id)
  )
)

;; Create auction for artwork
(define-public (create-auction 
  (artwork-id uint)
  (starting-price uint)
  (auction-duration-blocks uint)
  (reserve-price uint)
  (royalty-recipient principal)
  (royalty-percentage uint)
)
  (let (
    (listing-id (var-get next-listing-id))
    (auction-id (var-get next-auction-id))
    (seller tx-sender)
    (auction-end-block (+ burn-block-height auction-duration-blocks))
  )
    (asserts! (> starting-price u0) err-invalid-input)
    (asserts! (>= auction-duration-blocks (var-get min-auction-duration)) err-invalid-input)
    (asserts! (>= reserve-price starting-price) err-invalid-input)
    (asserts! (<= royalty-percentage u1000) err-invalid-input)
    
    ;; Create listing
    (map-set artwork-listings
      { listing-id: listing-id }
      {
        artwork-id: artwork-id,
        seller: seller,
        price: starting-price,
        sale-status: sale-status-auction,
        listing-timestamp: burn-block-height,
        expiry-timestamp: auction-end-block,
        royalty-recipient: royalty-recipient,
        royalty-percentage: royalty-percentage,
        description: u"Auction listing"
      }
    )
    
    ;; Create auction
    (map-set artwork-auctions
      { auction-id: auction-id }
      {
        listing-id: listing-id,
        artwork-id: artwork-id,
        seller: seller,
        starting-price: starting-price,
        current-highest-bid: starting-price,
        highest-bidder: none,
        auction-end-block: auction-end-block,
        total-bids: u0,
        reserve-price: reserve-price,
        is-active: true
      }
    )
    
    (var-set next-listing-id (+ listing-id u1))
    (var-set next-auction-id (+ auction-id u1))
    
    (print { event: "auction-created", auction-id: auction-id, artwork-id: artwork-id, starting-price: starting-price })
    (ok auction-id)
  )
)

;; Place bid on auction
(define-public (place-bid (auction-id uint) (bid-amount uint))
  (let (
    (auction-data (unwrap! (map-get? artwork-auctions { auction-id: auction-id }) err-not-found))
    (bidder tx-sender)
    (current-bid-count (get total-bids auction-data))
  )
    (asserts! (get is-active auction-data) err-auction-ended)
    (asserts! (<= burn-block-height (get auction-end-block auction-data)) err-auction-ended)
    (asserts! (> bid-amount (get current-highest-bid auction-data)) err-invalid-bid)
    (asserts! (not (is-eq bidder (get seller auction-data))) err-unauthorized)
    
    ;; Record bid in history
    (map-set bid-history
      { auction-id: auction-id, bid-sequence: current-bid-count }
      {
        bidder: bidder,
        bid-amount: bid-amount,
        bid-timestamp: burn-block-height,
        is-winning-bid: true
      }
    )
    
    ;; Update previous winning bid status if exists
    (if (> current-bid-count u0)
      (map-set bid-history
        { auction-id: auction-id, bid-sequence: (- current-bid-count u1) }
        (merge 
          (unwrap! (map-get? bid-history { auction-id: auction-id, bid-sequence: (- current-bid-count u1) }) err-not-found)
          { is-winning-bid: false }
        )
      )
      true
    )
    
    ;; Update auction with new highest bid
    (map-set artwork-auctions
      { auction-id: auction-id }
      (merge auction-data {
        current-highest-bid: bid-amount,
        highest-bidder: (some bidder),
        total-bids: (+ current-bid-count u1)
      })
    )
    
    (print { event: "bid-placed", auction-id: auction-id, bidder: bidder, amount: bid-amount })
    (ok true)
  )
)

;; Create gallery
(define-public (create-gallery 
  (name (string-utf8 256))
  (description (string-utf8 1024))
  (gallery-type uint)
  (is-public bool)
  (metadata-hash (string-ascii 64))
)
  (let (
    (gallery-id (var-get next-gallery-id))
    (owner tx-sender)
  )
    (asserts! (> (len name) u0) err-invalid-input)
    (asserts! (<= gallery-type gallery-type-private) err-invalid-input)
    
    (map-set galleries
      { gallery-id: gallery-id }
      {
        owner: owner,
        name: name,
        description: description,
        gallery-type: gallery-type,
        creation-timestamp: burn-block-height,
        artwork-count: u0,
        is-public: is-public,
        featured-artwork: none,
        metadata-hash: metadata-hash
      }
    )
    
    (var-set next-gallery-id (+ gallery-id u1))
    
    (print { event: "gallery-created", gallery-id: gallery-id, owner: owner, name: name })
    (ok gallery-id)
  )
)

;; Add artwork to gallery
(define-public (add-artwork-to-gallery 
  (gallery-id uint)
  (artwork-id uint)
  (display-order uint)
  (curator-notes (string-utf8 256))
)
  (let (
    (gallery-data (unwrap! (map-get? galleries { gallery-id: gallery-id }) err-not-found))
    (current-count (get artwork-count gallery-data))
  )
    (asserts! (is-eq tx-sender (get owner gallery-data)) err-unauthorized)
    (asserts! (< current-count (var-get max-gallery-artworks)) err-gallery-full)
    
    (map-set gallery-artworks
      { gallery-id: gallery-id, artwork-slot: current-count }
      {
        artwork-id: artwork-id,
        added-timestamp: burn-block-height,
        display-order: display-order,
        curator-notes: curator-notes
      }
    )
    
    (map-set galleries
      { gallery-id: gallery-id }
      (merge gallery-data { artwork-count: (+ current-count u1) })
    )
    
    (print { event: "artwork-added-to-gallery", gallery-id: gallery-id, artwork-id: artwork-id })
    (ok true)
  )
)

;; =============================================================================
;; READ-ONLY FUNCTIONS
;; =============================================================================

;; Get listing details
(define-read-only (get-listing-details (listing-id uint))
  (map-get? artwork-listings { listing-id: listing-id })
)

;; Get auction details
(define-read-only (get-auction-details (auction-id uint))
  (map-get? artwork-auctions { auction-id: auction-id })
)

;; Get gallery information
(define-read-only (get-gallery-info (gallery-id uint))
  (map-get? galleries { gallery-id: gallery-id })
)

;; Get gallery artwork
(define-read-only (get-gallery-artwork (gallery-id uint) (artwork-slot uint))
  (map-get? gallery-artworks { gallery-id: gallery-id, artwork-slot: artwork-slot })
)

;; Get collector portfolio
(define-read-only (get-collector-portfolio (collector-address principal))
  (map-get? collector-portfolios { collector-address: collector-address })
)

;; Get marketplace statistics
(define-read-only (get-marketplace-stats)
  {
    total-listings: (- (var-get next-listing-id) u1),
    total-auctions: (- (var-get next-auction-id) u1),
    total-galleries: (- (var-get next-gallery-id) u1),
    total-sales-volume: (var-get total-sales-volume),
    total-transactions: (var-get total-transactions),
    platform-fee: (var-get platform-fee-percentage)
  }
)

;; =============================================================================
;; PRIVATE FUNCTIONS
;; =============================================================================

;; Calculate platform fees
(define-private (calculate-platform-fee (sale-price uint))
  (/ (* sale-price (var-get platform-fee-percentage)) u10000)
)

;; Calculate royalty payment
(define-private (calculate-royalty-payment (sale-price uint) (royalty-percentage uint))
  (/ (* sale-price royalty-percentage) u10000)
)

;; Update sales metrics
(define-private (update-sales-metrics (sale-price uint) (buyer principal) (seller principal))
  (begin
    (var-set total-sales-volume (+ (var-get total-sales-volume) sale-price))
    (var-set total-transactions (+ (var-get total-transactions) u1))
    (ok true)
  )
)

