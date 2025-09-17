;; Art Authentication Registry Smart Contract
;; Manages digital art authentication with blockchain-verified certificates,
;; handles NFT minting with comprehensive provenance tracking, processes artist
;; verification and credentialing systems, maintains detailed artwork metadata
;; and creation history, and provides authenticity validation services.

;; =============================================================================
;; CONSTANTS
;; =============================================================================

(define-constant contract-owner tx-sender)
(define-constant err-owner-only (err u100))
(define-constant err-not-found (err u101))
(define-constant err-already-exists (err u102))
(define-constant err-unauthorized (err u103))
(define-constant err-invalid-input (err u104))
(define-constant err-insufficient-funds (err u105))
(define-constant err-artwork-not-available (err u106))
(define-constant err-artist-not-verified (err u107))
(define-constant err-invalid-metadata (err u108))

;; Authentication status constants
(define-constant status-pending u0)
(define-constant status-verified u1)
(define-constant status-rejected u2)

;; Artwork type constants
(define-constant type-digital-painting u1)
(define-constant type-digital-photography u2)
(define-constant type-digital-sculpture u3)
(define-constant type-generative-art u4)
(define-constant type-mixed-media u5)

;; =============================================================================
;; DATA VARIABLES
;; =============================================================================

(define-data-var next-artwork-id uint u1)
(define-data-var next-certificate-id uint u1)
(define-data-var platform-fee-percentage uint u250) ;; 2.5%
(define-data-var total-artworks-minted uint u0)
(define-data-var total-certificates-issued uint u0)
(define-data-var authentication-fee uint u1000000) ;; 1 STX in microSTX

;; =============================================================================
;; DATA MAPS
;; =============================================================================

;; Artist verification registry
(define-map artists-registry
  { artist-address: principal }
  {
    verification-status: uint,
    verification-timestamp: uint,
    total-artworks: uint,
    reputation-score: uint,
    profile-hash: (string-ascii 64),
    credentials-hash: (string-ascii 64)
  }
)

;; Artwork metadata and authentication
(define-map artworks-registry
  { artwork-id: uint }
  {
    artist: principal,
    title: (string-utf8 256),
    description: (string-utf8 1024),
    artwork-type: uint,
    creation-timestamp: uint,
    authentication-timestamp: uint,
    metadata-hash: (string-ascii 64),
    provenance-hash: (string-ascii 64),
    is-authenticated: bool,
    edition-number: uint,
    total-editions: uint,
    royalty-percentage: uint
  }
)

;; Authentication certificates
(define-map authentication-certificates
  { certificate-id: uint }
  {
    artwork-id: uint,
    issuer: principal,
    certificate-hash: (string-ascii 64),
    issue-timestamp: uint,
    validity-period: uint,
    verification-methods: (list 10 (string-ascii 32)),
    authenticity-score: uint
  }
)

;; Ownership tracking for provenance
(define-map ownership-history
  { artwork-id: uint, sequence-number: uint }
  {
    previous-owner: (optional principal),
    current-owner: principal,
    transfer-timestamp: uint,
    transfer-value: uint,
    transaction-hash: (string-ascii 64)
  }
)

;; Artist credentials and portfolio
(define-map artist-credentials
  { artist-address: principal, credential-type: (string-ascii 32) }
  {
    credential-value: (string-utf8 512),
    verification-source: principal,
    issue-date: uint,
    expiry-date: uint,
    is-active: bool
  }
)

;; =============================================================================
;; PUBLIC FUNCTIONS
;; =============================================================================

;; Register a new artist with verification process
(define-public (register-artist (profile-hash (string-ascii 64)) (credentials-hash (string-ascii 64)))
  (let (
    (artist-address tx-sender)
  )
    (asserts! (is-eq (map-get? artists-registry { artist-address: artist-address }) none) err-already-exists)
    (map-set artists-registry
      { artist-address: artist-address }
      {
        verification-status: status-pending,
        verification-timestamp: burn-block-height,
        total-artworks: u0,
        reputation-score: u100,
        profile-hash: profile-hash,
        credentials-hash: credentials-hash
      }
    )
    (print { event: "artist-registered", artist: artist-address, timestamp: burn-block-height })
    (ok artist-address)
  )
)

;; Verify artist (admin only)
(define-public (verify-artist (artist-address principal) (new-status uint))
  (begin
    (asserts! (is-eq tx-sender contract-owner) err-owner-only)
    (asserts! (is-some (map-get? artists-registry { artist-address: artist-address })) err-not-found)
    (map-set artists-registry
      { artist-address: artist-address }
      (merge 
        (unwrap! (map-get? artists-registry { artist-address: artist-address }) err-not-found)
        {
          verification-status: new-status,
          verification-timestamp: burn-block-height
        }
      )
    )
    (print { event: "artist-verification-updated", artist: artist-address, status: new-status })
    (ok true)
  )
)

;; Mint new artwork with authentication
(define-public (mint-artwork 
  (title (string-utf8 256))
  (description (string-utf8 1024))
  (artwork-type uint)
  (metadata-hash (string-ascii 64))
  (total-editions uint)
  (royalty-percentage uint)
)
  (let (
    (artwork-id (var-get next-artwork-id))
    (artist tx-sender)
    (artist-data (unwrap! (map-get? artists-registry { artist-address: artist }) err-artist-not-verified))
  )
    ;; Verify artist is authenticated
    (asserts! (is-eq (get verification-status artist-data) status-verified) err-artist-not-verified)
    (asserts! (<= royalty-percentage u1000) err-invalid-input) ;; Max 10% royalty
    (asserts! (> total-editions u0) err-invalid-input)
    
    ;; Create artwork record
    (map-set artworks-registry
      { artwork-id: artwork-id }
      {
        artist: artist,
        title: title,
        description: description,
        artwork-type: artwork-type,
        creation-timestamp: burn-block-height,
        authentication-timestamp: burn-block-height,
        metadata-hash: metadata-hash,
        provenance-hash: metadata-hash,
        is-authenticated: true,
        edition-number: u1,
        total-editions: total-editions,
        royalty-percentage: royalty-percentage
      }
    )
    
    ;; Initialize ownership history
    (map-set ownership-history
      { artwork-id: artwork-id, sequence-number: u0 }
      {
        previous-owner: none,
        current-owner: artist,
        transfer-timestamp: burn-block-height,
        transfer-value: u0,
        transaction-hash: ""
      }
    )
    
    ;; Update counters
    (var-set next-artwork-id (+ artwork-id u1))
    (var-set total-artworks-minted (+ (var-get total-artworks-minted) u1))
    
    ;; Update artist stats
    (map-set artists-registry
      { artist-address: artist }
      (merge artist-data { total-artworks: (+ (get total-artworks artist-data) u1) })
    )
    
    (print { event: "artwork-minted", artwork-id: artwork-id, artist: artist })
    (ok artwork-id)
  )
)

;; Issue authentication certificate
(define-public (issue-certificate 
  (artwork-id uint)
  (certificate-hash (string-ascii 64))
  (validity-period uint)
  (verification-methods (list 10 (string-ascii 32)))
  (authenticity-score uint)
)
  (let (
    (certificate-id (var-get next-certificate-id))
    (artwork-data (unwrap! (map-get? artworks-registry { artwork-id: artwork-id }) err-not-found))
  )
    (asserts! (is-eq tx-sender contract-owner) err-owner-only)
    (asserts! (<= authenticity-score u100) err-invalid-input)
    
    (map-set authentication-certificates
      { certificate-id: certificate-id }
      {
        artwork-id: artwork-id,
        issuer: tx-sender,
        certificate-hash: certificate-hash,
        issue-timestamp: burn-block-height,
        validity-period: validity-period,
        verification-methods: verification-methods,
        authenticity-score: authenticity-score
      }
    )
    
    (var-set next-certificate-id (+ certificate-id u1))
    (var-set total-certificates-issued (+ (var-get total-certificates-issued) u1))
    
    (print { event: "certificate-issued", certificate-id: certificate-id, artwork-id: artwork-id })
    (ok certificate-id)
  )
)

;; =============================================================================
;; READ-ONLY FUNCTIONS
;; =============================================================================

;; Get artist information
(define-read-only (get-artist-info (artist-address principal))
  (map-get? artists-registry { artist-address: artist-address })
)

;; Get artwork details
(define-read-only (get-artwork-details (artwork-id uint))
  (map-get? artworks-registry { artwork-id: artwork-id })
)

;; Get authentication certificate
(define-read-only (get-certificate (certificate-id uint))
  (map-get? authentication-certificates { certificate-id: certificate-id })
)

;; Get ownership history
(define-read-only (get-ownership-history (artwork-id uint) (sequence-number uint))
  (map-get? ownership-history { artwork-id: artwork-id, sequence-number: sequence-number })
)

;; Validate artwork authenticity
(define-read-only (validate-authenticity (artwork-id uint))
  (let (
    (artwork-data (map-get? artworks-registry { artwork-id: artwork-id }))
  )
    (match artwork-data
      artwork (ok (get is-authenticated artwork))
      err-not-found
    )
  )
)

;; Get platform statistics
(define-read-only (get-platform-stats)
  {
    total-artworks: (var-get total-artworks-minted),
    total-certificates: (var-get total-certificates-issued),
    authentication-fee: (var-get authentication-fee),
    platform-fee: (var-get platform-fee-percentage)
  }
)

;; =============================================================================
;; PRIVATE FUNCTIONS
;; =============================================================================

;; Calculate authentication score based on multiple factors
(define-private (calculate-authenticity-score (artist principal) (artwork-metadata (string-ascii 64)))
  (let (
    (artist-data (default-to 
      { verification-status: u0, verification-timestamp: u0, total-artworks: u0, 
        reputation-score: u0, profile-hash: "", credentials-hash: "" }
      (map-get? artists-registry { artist-address: artist })
    ))
    (base-score u50)
    (verification-bonus (if (is-eq (get verification-status artist-data) status-verified) u30 u0))
    (experience-bonus (if (<= (get total-artworks artist-data) u20) (get total-artworks artist-data) u20))
  )
    (+ base-score verification-bonus experience-bonus)
  )
)

;; Update artist reputation based on activity
(define-private (update-artist-reputation (artist principal) (score-change int))
  (let (
    (current-data (unwrap! (map-get? artists-registry { artist-address: artist }) err-not-found))
    (current-score (get reputation-score current-data))
    (new-score (if (> score-change 0)
      (if (<= (+ current-score (to-uint score-change)) u1000) (+ current-score (to-uint score-change)) u1000)
      (if (> current-score (to-uint (- score-change)))
        (- current-score (to-uint (- score-change)))
        u0
      )
    ))
  )
    (map-set artists-registry
      { artist-address: artist }
      (merge current-data { reputation-score: new-score })
    )
    (ok new-score)
  )
)

