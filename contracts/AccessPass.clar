;; contracts/access-pass.clar

(define-constant ERR_NOT_ADMINISTRATOR u100)
(define-constant ERR_MEMBERSHIP_EXISTS u101)
(define-constant ERR_MEMBERSHIP_NOT_FOUND u102)
(define-constant ERR_NOT_MEMBERSHIP_OWNER u103)
(define-constant ERR_MEMBERSHIP_ALREADY_ACTIVATED u104)

(define-data-var membership-counter uint u0)
(define-map memberships uint 
    (tuple (owner principal) (fee uint) (activated bool)))
(define-map revenues principal uint)

(define-public (create-membership (membership-id uint) (fee uint))
    (begin
        ;; Ensure only the contract deployer (administrator) can create memberships
        (asserts! (is-eq tx-sender (as-contract tx-sender)) (err ERR_NOT_ADMINISTRATOR))
        ;; Ensure the membership doesn't already exist
        (asserts! (is-none (map-get? memberships membership-id)) (err ERR_MEMBERSHIP_EXISTS))
        ;; Ensure fee is valid (non-negative)
        (asserts! (>= fee u0) (err u107))
        ;; Store the membership with the initial state
        (map-set memberships membership-id { owner: tx-sender, fee: fee, activated: false })
        ;; Increment membership counter
        (var-set membership-counter (+ (var-get membership-counter) u1))
        ;; Verify the membership was created successfully
        (match (map-get? memberships membership-id)
            membership-data (ok membership-id)
            (err ERR_MEMBERSHIP_NOT_FOUND)
        )
    )
)

(define-public (purchase-membership (membership-id uint))
    (let (
        (membership (map-get? memberships membership-id))
    )
        (begin
            ;; Ensure the membership exists
            (asserts! (is-some membership) (err ERR_MEMBERSHIP_NOT_FOUND))
            ;; Unwrap the membership data
            (let (
                (membership-data (unwrap-panic membership))
                (membership-fee (get fee membership-data))
                (membership-owner (get owner membership-data))
                (membership-activated (get activated membership-data))
            )
                ;; Ensure the membership is not already activated
                (asserts! (not membership-activated) (err ERR_MEMBERSHIP_ALREADY_ACTIVATED))
                ;; Ensure the buyer pays enough funds
                (match (stx-transfer? membership-fee tx-sender membership-owner)
                    success
                    (begin
                        ;; Transfer the membership to the buyer
                        (map-set memberships membership-id { owner: tx-sender, fee: membership-fee, activated: true })
                        ;; Update revenues for administrator
                        (let ((current-revenue (default-to u0 (map-get? revenues membership-owner))))
                            (map-set revenues membership-owner (+ current-revenue membership-fee))
                        )
                        (ok membership-id)
                    )
                    error (err u106)
                )
            )
        )
    )
)

(define-public (transfer-membership (membership-id uint) (recipient principal))
    (let (
        (membership (map-get? memberships membership-id))
    )
        (begin
            ;; Ensure the membership exists
            (asserts! (is-some membership) (err ERR_MEMBERSHIP_NOT_FOUND))
            ;; Unwrap the membership data
            (let (
                (membership-data (unwrap-panic membership))
                (membership-owner (get owner membership-data))
            )
                ;; Ensure the caller owns the membership
                (asserts! (is-eq membership-owner tx-sender) (err ERR_NOT_MEMBERSHIP_OWNER))
                ;; Ensure recipient is not null
                (asserts! (is-some (some recipient)) (err u108))
                ;; Transfer membership ownership
                (map-set memberships membership-id { owner: recipient, fee: (get fee membership-data), activated: true })
                (ok recipient)
            )
        )
    )
)

(define-public (collect-revenue)
    (let (
        (revenue (default-to u0 (map-get? revenues tx-sender)))
    )
        (begin
            ;; Ensure the user has revenue to collect
            (asserts! (> revenue u0) (err u105))
            ;; Transfer funds to the user
            (match (stx-transfer? revenue (as-contract tx-sender) tx-sender)
                success (begin
                    ;; Reset revenue to zero only if transfer succeeded
                    (map-delete revenues tx-sender)
                    (ok revenue)
                )
                error (err u106)
            )
        )
    )
)