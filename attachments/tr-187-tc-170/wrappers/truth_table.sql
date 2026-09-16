SELECT t.k,
  CASE WHEN (CASE
                WHEN so.STATUS = 'Cancelled' THEN 'Canceled'
                WHEN COALESCE(rpr.PAID_AMOUNT, 0) > 0
                        AND COALESCE(rpr.PAID_AMOUNT, 0) >= COALESCE(so.AMOUNT, 0) THEN 'Paid'
                WHEN COALESCE(rpr.PAID_AMOUNT, 0) > 0 THEN 'Reserved/Partially Paid'
                WHEN so.STATUS IN ('Complete', 'Finalized')
                        AND COALESCE(so.AMOUNT, 0) <= 0 THEN 'Paid'
                WHEN so.STATUS IN ('Complete', 'Finalized', 'Confirmed') THEN 'Signed Contract'
                WHEN so.STATUS = 'Tentative' THEN 'Proposal/Negotiation'
                WHEN so.STATUS = 'Pending' THEN 'Inquiry'
                WHEN so.STATUS IN ('Reserved', 'Unresolved') THEN 'Reserved/Partially Paid'
                ELSE 'Inquiry'
        END) IS NULL THEN 0 WHEN (CASE
                WHEN so.STATUS = 'Cancelled' THEN 'Canceled'
                WHEN COALESCE(rpr.PAID_AMOUNT, 0) > 0
                        AND COALESCE(rpr.PAID_AMOUNT, 0) >= COALESCE(so.AMOUNT, 0) THEN 'Paid'
                WHEN COALESCE(rpr.PAID_AMOUNT, 0) > 0 THEN 'Reserved/Partially Paid'
                WHEN so.STATUS IN ('Complete', 'Finalized')
                        AND COALESCE(so.AMOUNT, 0) <= 0 THEN 'Paid'
                WHEN so.STATUS IN ('Complete', 'Finalized', 'Confirmed') THEN 'Signed Contract'
                WHEN so.STATUS = 'Tentative' THEN 'Proposal/Negotiation'
                WHEN so.STATUS = 'Pending' THEN 'Inquiry'
                WHEN so.STATUS IN ('Reserved', 'Unresolved') THEN 'Reserved/Partially Paid'
                ELSE 'Inquiry'
        END) = 'Canceled' THEN 1 WHEN (CASE
                WHEN so.STATUS = 'Cancelled' THEN 'Canceled'
                WHEN COALESCE(rpr.PAID_AMOUNT, 0) > 0
                        AND COALESCE(rpr.PAID_AMOUNT, 0) >= COALESCE(so.AMOUNT, 0) THEN 'Paid'
                WHEN COALESCE(rpr.PAID_AMOUNT, 0) > 0 THEN 'Reserved/Partially Paid'
                WHEN so.STATUS IN ('Complete', 'Finalized')
                        AND COALESCE(so.AMOUNT, 0) <= 0 THEN 'Paid'
                WHEN so.STATUS IN ('Complete', 'Finalized', 'Confirmed') THEN 'Signed Contract'
                WHEN so.STATUS = 'Tentative' THEN 'Proposal/Negotiation'
                WHEN so.STATUS = 'Pending' THEN 'Inquiry'
                WHEN so.STATUS IN ('Reserved', 'Unresolved') THEN 'Reserved/Partially Paid'
                ELSE 'Inquiry'
        END) = 'Paid' THEN 2 WHEN (CASE
                WHEN so.STATUS = 'Cancelled' THEN 'Canceled'
                WHEN COALESCE(rpr.PAID_AMOUNT, 0) > 0
                        AND COALESCE(rpr.PAID_AMOUNT, 0) >= COALESCE(so.AMOUNT, 0) THEN 'Paid'
                WHEN COALESCE(rpr.PAID_AMOUNT, 0) > 0 THEN 'Reserved/Partially Paid'
                WHEN so.STATUS IN ('Complete', 'Finalized')
                        AND COALESCE(so.AMOUNT, 0) <= 0 THEN 'Paid'
                WHEN so.STATUS IN ('Complete', 'Finalized', 'Confirmed') THEN 'Signed Contract'
                WHEN so.STATUS = 'Tentative' THEN 'Proposal/Negotiation'
                WHEN so.STATUS = 'Pending' THEN 'Inquiry'
                WHEN so.STATUS IN ('Reserved', 'Unresolved') THEN 'Reserved/Partially Paid'
                ELSE 'Inquiry'
        END) = 'Reserved/Partially Paid' THEN 3 WHEN (CASE
                WHEN so.STATUS = 'Cancelled' THEN 'Canceled'
                WHEN COALESCE(rpr.PAID_AMOUNT, 0) > 0
                        AND COALESCE(rpr.PAID_AMOUNT, 0) >= COALESCE(so.AMOUNT, 0) THEN 'Paid'
                WHEN COALESCE(rpr.PAID_AMOUNT, 0) > 0 THEN 'Reserved/Partially Paid'
                WHEN so.STATUS IN ('Complete', 'Finalized')
                        AND COALESCE(so.AMOUNT, 0) <= 0 THEN 'Paid'
                WHEN so.STATUS IN ('Complete', 'Finalized', 'Confirmed') THEN 'Signed Contract'
                WHEN so.STATUS = 'Tentative' THEN 'Proposal/Negotiation'
                WHEN so.STATUS = 'Pending' THEN 'Inquiry'
                WHEN so.STATUS IN ('Reserved', 'Unresolved') THEN 'Reserved/Partially Paid'
                ELSE 'Inquiry'
        END) = 'Signed Contract' THEN 4 WHEN (CASE
                WHEN so.STATUS = 'Cancelled' THEN 'Canceled'
                WHEN COALESCE(rpr.PAID_AMOUNT, 0) > 0
                        AND COALESCE(rpr.PAID_AMOUNT, 0) >= COALESCE(so.AMOUNT, 0) THEN 'Paid'
                WHEN COALESCE(rpr.PAID_AMOUNT, 0) > 0 THEN 'Reserved/Partially Paid'
                WHEN so.STATUS IN ('Complete', 'Finalized')
                        AND COALESCE(so.AMOUNT, 0) <= 0 THEN 'Paid'
                WHEN so.STATUS IN ('Complete', 'Finalized', 'Confirmed') THEN 'Signed Contract'
                WHEN so.STATUS = 'Tentative' THEN 'Proposal/Negotiation'
                WHEN so.STATUS = 'Pending' THEN 'Inquiry'
                WHEN so.STATUS IN ('Reserved', 'Unresolved') THEN 'Reserved/Partially Paid'
                ELSE 'Inquiry'
        END) = 'Proposal/Negotiation' THEN 5 WHEN (CASE
                WHEN so.STATUS = 'Cancelled' THEN 'Canceled'
                WHEN COALESCE(rpr.PAID_AMOUNT, 0) > 0
                        AND COALESCE(rpr.PAID_AMOUNT, 0) >= COALESCE(so.AMOUNT, 0) THEN 'Paid'
                WHEN COALESCE(rpr.PAID_AMOUNT, 0) > 0 THEN 'Reserved/Partially Paid'
                WHEN so.STATUS IN ('Complete', 'Finalized')
                        AND COALESCE(so.AMOUNT, 0) <= 0 THEN 'Paid'
                WHEN so.STATUS IN ('Complete', 'Finalized', 'Confirmed') THEN 'Signed Contract'
                WHEN so.STATUS = 'Tentative' THEN 'Proposal/Negotiation'
                WHEN so.STATUS = 'Pending' THEN 'Inquiry'
                WHEN so.STATUS IN ('Reserved', 'Unresolved') THEN 'Reserved/Partially Paid'
                ELSE 'Inquiry'
        END) = 'Inquiry' THEN 6 WHEN (CASE
                WHEN so.STATUS = 'Cancelled' THEN 'Canceled'
                WHEN COALESCE(rpr.PAID_AMOUNT, 0) > 0
                        AND COALESCE(rpr.PAID_AMOUNT, 0) >= COALESCE(so.AMOUNT, 0) THEN 'Paid'
                WHEN COALESCE(rpr.PAID_AMOUNT, 0) > 0 THEN 'Reserved/Partially Paid'
                WHEN so.STATUS IN ('Complete', 'Finalized')
                        AND COALESCE(so.AMOUNT, 0) <= 0 THEN 'Paid'
                WHEN so.STATUS IN ('Complete', 'Finalized', 'Confirmed') THEN 'Signed Contract'
                WHEN so.STATUS = 'Tentative' THEN 'Proposal/Negotiation'
                WHEN so.STATUS = 'Pending' THEN 'Inquiry'
                WHEN so.STATUS IN ('Reserved', 'Unresolved') THEN 'Reserved/Partially Paid'
                ELSE 'Inquiry'
        END) = 'Pending' THEN 11 WHEN (CASE
                WHEN so.STATUS = 'Cancelled' THEN 'Canceled'
                WHEN COALESCE(rpr.PAID_AMOUNT, 0) > 0
                        AND COALESCE(rpr.PAID_AMOUNT, 0) >= COALESCE(so.AMOUNT, 0) THEN 'Paid'
                WHEN COALESCE(rpr.PAID_AMOUNT, 0) > 0 THEN 'Reserved/Partially Paid'
                WHEN so.STATUS IN ('Complete', 'Finalized')
                        AND COALESCE(so.AMOUNT, 0) <= 0 THEN 'Paid'
                WHEN so.STATUS IN ('Complete', 'Finalized', 'Confirmed') THEN 'Signed Contract'
                WHEN so.STATUS = 'Tentative' THEN 'Proposal/Negotiation'
                WHEN so.STATUS = 'Pending' THEN 'Inquiry'
                WHEN so.STATUS IN ('Reserved', 'Unresolved') THEN 'Reserved/Partially Paid'
                ELSE 'Inquiry'
        END) = 'Complete' THEN 12 WHEN (CASE
                WHEN so.STATUS = 'Cancelled' THEN 'Canceled'
                WHEN COALESCE(rpr.PAID_AMOUNT, 0) > 0
                        AND COALESCE(rpr.PAID_AMOUNT, 0) >= COALESCE(so.AMOUNT, 0) THEN 'Paid'
                WHEN COALESCE(rpr.PAID_AMOUNT, 0) > 0 THEN 'Reserved/Partially Paid'
                WHEN so.STATUS IN ('Complete', 'Finalized')
                        AND COALESCE(so.AMOUNT, 0) <= 0 THEN 'Paid'
                WHEN so.STATUS IN ('Complete', 'Finalized', 'Confirmed') THEN 'Signed Contract'
                WHEN so.STATUS = 'Tentative' THEN 'Proposal/Negotiation'
                WHEN so.STATUS = 'Pending' THEN 'Inquiry'
                WHEN so.STATUS IN ('Reserved', 'Unresolved') THEN 'Reserved/Partially Paid'
                ELSE 'Inquiry'
        END) = 'Tentative' THEN 13 WHEN (CASE
                WHEN so.STATUS = 'Cancelled' THEN 'Canceled'
                WHEN COALESCE(rpr.PAID_AMOUNT, 0) > 0
                        AND COALESCE(rpr.PAID_AMOUNT, 0) >= COALESCE(so.AMOUNT, 0) THEN 'Paid'
                WHEN COALESCE(rpr.PAID_AMOUNT, 0) > 0 THEN 'Reserved/Partially Paid'
                WHEN so.STATUS IN ('Complete', 'Finalized')
                        AND COALESCE(so.AMOUNT, 0) <= 0 THEN 'Paid'
                WHEN so.STATUS IN ('Complete', 'Finalized', 'Confirmed') THEN 'Signed Contract'
                WHEN so.STATUS = 'Tentative' THEN 'Proposal/Negotiation'
                WHEN so.STATUS = 'Pending' THEN 'Inquiry'
                WHEN so.STATUS IN ('Reserved', 'Unresolved') THEN 'Reserved/Partially Paid'
                ELSE 'Inquiry'
        END) = 'Confirmed' THEN 14 WHEN (CASE
                WHEN so.STATUS = 'Cancelled' THEN 'Canceled'
                WHEN COALESCE(rpr.PAID_AMOUNT, 0) > 0
                        AND COALESCE(rpr.PAID_AMOUNT, 0) >= COALESCE(so.AMOUNT, 0) THEN 'Paid'
                WHEN COALESCE(rpr.PAID_AMOUNT, 0) > 0 THEN 'Reserved/Partially Paid'
                WHEN so.STATUS IN ('Complete', 'Finalized')
                        AND COALESCE(so.AMOUNT, 0) <= 0 THEN 'Paid'
                WHEN so.STATUS IN ('Complete', 'Finalized', 'Confirmed') THEN 'Signed Contract'
                WHEN so.STATUS = 'Tentative' THEN 'Proposal/Negotiation'
                WHEN so.STATUS = 'Pending' THEN 'Inquiry'
                WHEN so.STATUS IN ('Reserved', 'Unresolved') THEN 'Reserved/Partially Paid'
                ELSE 'Inquiry'
        END) = 'Finalized' THEN 15 WHEN (CASE
                WHEN so.STATUS = 'Cancelled' THEN 'Canceled'
                WHEN COALESCE(rpr.PAID_AMOUNT, 0) > 0
                        AND COALESCE(rpr.PAID_AMOUNT, 0) >= COALESCE(so.AMOUNT, 0) THEN 'Paid'
                WHEN COALESCE(rpr.PAID_AMOUNT, 0) > 0 THEN 'Reserved/Partially Paid'
                WHEN so.STATUS IN ('Complete', 'Finalized')
                        AND COALESCE(so.AMOUNT, 0) <= 0 THEN 'Paid'
                WHEN so.STATUS IN ('Complete', 'Finalized', 'Confirmed') THEN 'Signed Contract'
                WHEN so.STATUS = 'Tentative' THEN 'Proposal/Negotiation'
                WHEN so.STATUS = 'Pending' THEN 'Inquiry'
                WHEN so.STATUS IN ('Reserved', 'Unresolved') THEN 'Reserved/Partially Paid'
                ELSE 'Inquiry'
        END) = 'Cancelled' THEN 16 WHEN (CASE
                WHEN so.STATUS = 'Cancelled' THEN 'Canceled'
                WHEN COALESCE(rpr.PAID_AMOUNT, 0) > 0
                        AND COALESCE(rpr.PAID_AMOUNT, 0) >= COALESCE(so.AMOUNT, 0) THEN 'Paid'
                WHEN COALESCE(rpr.PAID_AMOUNT, 0) > 0 THEN 'Reserved/Partially Paid'
                WHEN so.STATUS IN ('Complete', 'Finalized')
                        AND COALESCE(so.AMOUNT, 0) <= 0 THEN 'Paid'
                WHEN so.STATUS IN ('Complete', 'Finalized', 'Confirmed') THEN 'Signed Contract'
                WHEN so.STATUS = 'Tentative' THEN 'Proposal/Negotiation'
                WHEN so.STATUS = 'Pending' THEN 'Inquiry'
                WHEN so.STATUS IN ('Reserved', 'Unresolved') THEN 'Reserved/Partially Paid'
                ELSE 'Inquiry'
        END) = 'Reserved' THEN 17 WHEN (CASE
                WHEN so.STATUS = 'Cancelled' THEN 'Canceled'
                WHEN COALESCE(rpr.PAID_AMOUNT, 0) > 0
                        AND COALESCE(rpr.PAID_AMOUNT, 0) >= COALESCE(so.AMOUNT, 0) THEN 'Paid'
                WHEN COALESCE(rpr.PAID_AMOUNT, 0) > 0 THEN 'Reserved/Partially Paid'
                WHEN so.STATUS IN ('Complete', 'Finalized')
                        AND COALESCE(so.AMOUNT, 0) <= 0 THEN 'Paid'
                WHEN so.STATUS IN ('Complete', 'Finalized', 'Confirmed') THEN 'Signed Contract'
                WHEN so.STATUS = 'Tentative' THEN 'Proposal/Negotiation'
                WHEN so.STATUS = 'Pending' THEN 'Inquiry'
                WHEN so.STATUS IN ('Reserved', 'Unresolved') THEN 'Reserved/Partially Paid'
                ELSE 'Inquiry'
        END) = 'Unresolved' THEN 18 ELSE 99 END AS ev_post, CASE WHEN (CASE
                WHEN so.STATUS = 'Cancelled' THEN 'Canceled'
                WHEN COALESCE(rpr.PAID_AMOUNT, 0) > 0
                        AND COALESCE(rpr.PAID_AMOUNT, 0) >= COALESCE(so.AMOUNT, 0) THEN 'Paid'
                WHEN COALESCE(rpr.PAID_AMOUNT, 0) > 0 THEN 'Reserved/Partially Paid'
                WHEN so.STATUS IN ('Complete', 'Finalized')
                        AND COALESCE(so.AMOUNT, 0) <= 0 THEN 'Paid'
                WHEN so.STATUS IN ('Complete', 'Finalized', 'Confirmed') THEN 'Signed Contract'
                WHEN so.STATUS = 'Tentative' THEN 'Proposal/Negotiation'
                WHEN so.STATUS = 'Pending' THEN 'Inquiry'
                WHEN so.STATUS IN ('Reserved', 'Unresolved') THEN 'Reserved/Partially Paid'
                ELSE 'Inquiry'
        END) IS NULL THEN 0 WHEN (CASE
                WHEN so.STATUS = 'Cancelled' THEN 'Canceled'
                WHEN COALESCE(rpr.PAID_AMOUNT, 0) > 0
                        AND COALESCE(rpr.PAID_AMOUNT, 0) >= COALESCE(so.AMOUNT, 0) THEN 'Paid'
                WHEN COALESCE(rpr.PAID_AMOUNT, 0) > 0 THEN 'Reserved/Partially Paid'
                WHEN so.STATUS IN ('Complete', 'Finalized')
                        AND COALESCE(so.AMOUNT, 0) <= 0 THEN 'Paid'
                WHEN so.STATUS IN ('Complete', 'Finalized', 'Confirmed') THEN 'Signed Contract'
                WHEN so.STATUS = 'Tentative' THEN 'Proposal/Negotiation'
                WHEN so.STATUS = 'Pending' THEN 'Inquiry'
                WHEN so.STATUS IN ('Reserved', 'Unresolved') THEN 'Reserved/Partially Paid'
                ELSE 'Inquiry'
        END) = 'Canceled' THEN 1 WHEN (CASE
                WHEN so.STATUS = 'Cancelled' THEN 'Canceled'
                WHEN COALESCE(rpr.PAID_AMOUNT, 0) > 0
                        AND COALESCE(rpr.PAID_AMOUNT, 0) >= COALESCE(so.AMOUNT, 0) THEN 'Paid'
                WHEN COALESCE(rpr.PAID_AMOUNT, 0) > 0 THEN 'Reserved/Partially Paid'
                WHEN so.STATUS IN ('Complete', 'Finalized')
                        AND COALESCE(so.AMOUNT, 0) <= 0 THEN 'Paid'
                WHEN so.STATUS IN ('Complete', 'Finalized', 'Confirmed') THEN 'Signed Contract'
                WHEN so.STATUS = 'Tentative' THEN 'Proposal/Negotiation'
                WHEN so.STATUS = 'Pending' THEN 'Inquiry'
                WHEN so.STATUS IN ('Reserved', 'Unresolved') THEN 'Reserved/Partially Paid'
                ELSE 'Inquiry'
        END) = 'Paid' THEN 2 WHEN (CASE
                WHEN so.STATUS = 'Cancelled' THEN 'Canceled'
                WHEN COALESCE(rpr.PAID_AMOUNT, 0) > 0
                        AND COALESCE(rpr.PAID_AMOUNT, 0) >= COALESCE(so.AMOUNT, 0) THEN 'Paid'
                WHEN COALESCE(rpr.PAID_AMOUNT, 0) > 0 THEN 'Reserved/Partially Paid'
                WHEN so.STATUS IN ('Complete', 'Finalized')
                        AND COALESCE(so.AMOUNT, 0) <= 0 THEN 'Paid'
                WHEN so.STATUS IN ('Complete', 'Finalized', 'Confirmed') THEN 'Signed Contract'
                WHEN so.STATUS = 'Tentative' THEN 'Proposal/Negotiation'
                WHEN so.STATUS = 'Pending' THEN 'Inquiry'
                WHEN so.STATUS IN ('Reserved', 'Unresolved') THEN 'Reserved/Partially Paid'
                ELSE 'Inquiry'
        END) = 'Reserved/Partially Paid' THEN 3 WHEN (CASE
                WHEN so.STATUS = 'Cancelled' THEN 'Canceled'
                WHEN COALESCE(rpr.PAID_AMOUNT, 0) > 0
                        AND COALESCE(rpr.PAID_AMOUNT, 0) >= COALESCE(so.AMOUNT, 0) THEN 'Paid'
                WHEN COALESCE(rpr.PAID_AMOUNT, 0) > 0 THEN 'Reserved/Partially Paid'
                WHEN so.STATUS IN ('Complete', 'Finalized')
                        AND COALESCE(so.AMOUNT, 0) <= 0 THEN 'Paid'
                WHEN so.STATUS IN ('Complete', 'Finalized', 'Confirmed') THEN 'Signed Contract'
                WHEN so.STATUS = 'Tentative' THEN 'Proposal/Negotiation'
                WHEN so.STATUS = 'Pending' THEN 'Inquiry'
                WHEN so.STATUS IN ('Reserved', 'Unresolved') THEN 'Reserved/Partially Paid'
                ELSE 'Inquiry'
        END) = 'Signed Contract' THEN 4 WHEN (CASE
                WHEN so.STATUS = 'Cancelled' THEN 'Canceled'
                WHEN COALESCE(rpr.PAID_AMOUNT, 0) > 0
                        AND COALESCE(rpr.PAID_AMOUNT, 0) >= COALESCE(so.AMOUNT, 0) THEN 'Paid'
                WHEN COALESCE(rpr.PAID_AMOUNT, 0) > 0 THEN 'Reserved/Partially Paid'
                WHEN so.STATUS IN ('Complete', 'Finalized')
                        AND COALESCE(so.AMOUNT, 0) <= 0 THEN 'Paid'
                WHEN so.STATUS IN ('Complete', 'Finalized', 'Confirmed') THEN 'Signed Contract'
                WHEN so.STATUS = 'Tentative' THEN 'Proposal/Negotiation'
                WHEN so.STATUS = 'Pending' THEN 'Inquiry'
                WHEN so.STATUS IN ('Reserved', 'Unresolved') THEN 'Reserved/Partially Paid'
                ELSE 'Inquiry'
        END) = 'Proposal/Negotiation' THEN 5 WHEN (CASE
                WHEN so.STATUS = 'Cancelled' THEN 'Canceled'
                WHEN COALESCE(rpr.PAID_AMOUNT, 0) > 0
                        AND COALESCE(rpr.PAID_AMOUNT, 0) >= COALESCE(so.AMOUNT, 0) THEN 'Paid'
                WHEN COALESCE(rpr.PAID_AMOUNT, 0) > 0 THEN 'Reserved/Partially Paid'
                WHEN so.STATUS IN ('Complete', 'Finalized')
                        AND COALESCE(so.AMOUNT, 0) <= 0 THEN 'Paid'
                WHEN so.STATUS IN ('Complete', 'Finalized', 'Confirmed') THEN 'Signed Contract'
                WHEN so.STATUS = 'Tentative' THEN 'Proposal/Negotiation'
                WHEN so.STATUS = 'Pending' THEN 'Inquiry'
                WHEN so.STATUS IN ('Reserved', 'Unresolved') THEN 'Reserved/Partially Paid'
                ELSE 'Inquiry'
        END) = 'Inquiry' THEN 6 WHEN (CASE
                WHEN so.STATUS = 'Cancelled' THEN 'Canceled'
                WHEN COALESCE(rpr.PAID_AMOUNT, 0) > 0
                        AND COALESCE(rpr.PAID_AMOUNT, 0) >= COALESCE(so.AMOUNT, 0) THEN 'Paid'
                WHEN COALESCE(rpr.PAID_AMOUNT, 0) > 0 THEN 'Reserved/Partially Paid'
                WHEN so.STATUS IN ('Complete', 'Finalized')
                        AND COALESCE(so.AMOUNT, 0) <= 0 THEN 'Paid'
                WHEN so.STATUS IN ('Complete', 'Finalized', 'Confirmed') THEN 'Signed Contract'
                WHEN so.STATUS = 'Tentative' THEN 'Proposal/Negotiation'
                WHEN so.STATUS = 'Pending' THEN 'Inquiry'
                WHEN so.STATUS IN ('Reserved', 'Unresolved') THEN 'Reserved/Partially Paid'
                ELSE 'Inquiry'
        END) = 'Pending' THEN 11 WHEN (CASE
                WHEN so.STATUS = 'Cancelled' THEN 'Canceled'
                WHEN COALESCE(rpr.PAID_AMOUNT, 0) > 0
                        AND COALESCE(rpr.PAID_AMOUNT, 0) >= COALESCE(so.AMOUNT, 0) THEN 'Paid'
                WHEN COALESCE(rpr.PAID_AMOUNT, 0) > 0 THEN 'Reserved/Partially Paid'
                WHEN so.STATUS IN ('Complete', 'Finalized')
                        AND COALESCE(so.AMOUNT, 0) <= 0 THEN 'Paid'
                WHEN so.STATUS IN ('Complete', 'Finalized', 'Confirmed') THEN 'Signed Contract'
                WHEN so.STATUS = 'Tentative' THEN 'Proposal/Negotiation'
                WHEN so.STATUS = 'Pending' THEN 'Inquiry'
                WHEN so.STATUS IN ('Reserved', 'Unresolved') THEN 'Reserved/Partially Paid'
                ELSE 'Inquiry'
        END) = 'Complete' THEN 12 WHEN (CASE
                WHEN so.STATUS = 'Cancelled' THEN 'Canceled'
                WHEN COALESCE(rpr.PAID_AMOUNT, 0) > 0
                        AND COALESCE(rpr.PAID_AMOUNT, 0) >= COALESCE(so.AMOUNT, 0) THEN 'Paid'
                WHEN COALESCE(rpr.PAID_AMOUNT, 0) > 0 THEN 'Reserved/Partially Paid'
                WHEN so.STATUS IN ('Complete', 'Finalized')
                        AND COALESCE(so.AMOUNT, 0) <= 0 THEN 'Paid'
                WHEN so.STATUS IN ('Complete', 'Finalized', 'Confirmed') THEN 'Signed Contract'
                WHEN so.STATUS = 'Tentative' THEN 'Proposal/Negotiation'
                WHEN so.STATUS = 'Pending' THEN 'Inquiry'
                WHEN so.STATUS IN ('Reserved', 'Unresolved') THEN 'Reserved/Partially Paid'
                ELSE 'Inquiry'
        END) = 'Tentative' THEN 13 WHEN (CASE
                WHEN so.STATUS = 'Cancelled' THEN 'Canceled'
                WHEN COALESCE(rpr.PAID_AMOUNT, 0) > 0
                        AND COALESCE(rpr.PAID_AMOUNT, 0) >= COALESCE(so.AMOUNT, 0) THEN 'Paid'
                WHEN COALESCE(rpr.PAID_AMOUNT, 0) > 0 THEN 'Reserved/Partially Paid'
                WHEN so.STATUS IN ('Complete', 'Finalized')
                        AND COALESCE(so.AMOUNT, 0) <= 0 THEN 'Paid'
                WHEN so.STATUS IN ('Complete', 'Finalized', 'Confirmed') THEN 'Signed Contract'
                WHEN so.STATUS = 'Tentative' THEN 'Proposal/Negotiation'
                WHEN so.STATUS = 'Pending' THEN 'Inquiry'
                WHEN so.STATUS IN ('Reserved', 'Unresolved') THEN 'Reserved/Partially Paid'
                ELSE 'Inquiry'
        END) = 'Confirmed' THEN 14 WHEN (CASE
                WHEN so.STATUS = 'Cancelled' THEN 'Canceled'
                WHEN COALESCE(rpr.PAID_AMOUNT, 0) > 0
                        AND COALESCE(rpr.PAID_AMOUNT, 0) >= COALESCE(so.AMOUNT, 0) THEN 'Paid'
                WHEN COALESCE(rpr.PAID_AMOUNT, 0) > 0 THEN 'Reserved/Partially Paid'
                WHEN so.STATUS IN ('Complete', 'Finalized')
                        AND COALESCE(so.AMOUNT, 0) <= 0 THEN 'Paid'
                WHEN so.STATUS IN ('Complete', 'Finalized', 'Confirmed') THEN 'Signed Contract'
                WHEN so.STATUS = 'Tentative' THEN 'Proposal/Negotiation'
                WHEN so.STATUS = 'Pending' THEN 'Inquiry'
                WHEN so.STATUS IN ('Reserved', 'Unresolved') THEN 'Reserved/Partially Paid'
                ELSE 'Inquiry'
        END) = 'Finalized' THEN 15 WHEN (CASE
                WHEN so.STATUS = 'Cancelled' THEN 'Canceled'
                WHEN COALESCE(rpr.PAID_AMOUNT, 0) > 0
                        AND COALESCE(rpr.PAID_AMOUNT, 0) >= COALESCE(so.AMOUNT, 0) THEN 'Paid'
                WHEN COALESCE(rpr.PAID_AMOUNT, 0) > 0 THEN 'Reserved/Partially Paid'
                WHEN so.STATUS IN ('Complete', 'Finalized')
                        AND COALESCE(so.AMOUNT, 0) <= 0 THEN 'Paid'
                WHEN so.STATUS IN ('Complete', 'Finalized', 'Confirmed') THEN 'Signed Contract'
                WHEN so.STATUS = 'Tentative' THEN 'Proposal/Negotiation'
                WHEN so.STATUS = 'Pending' THEN 'Inquiry'
                WHEN so.STATUS IN ('Reserved', 'Unresolved') THEN 'Reserved/Partially Paid'
                ELSE 'Inquiry'
        END) = 'Cancelled' THEN 16 WHEN (CASE
                WHEN so.STATUS = 'Cancelled' THEN 'Canceled'
                WHEN COALESCE(rpr.PAID_AMOUNT, 0) > 0
                        AND COALESCE(rpr.PAID_AMOUNT, 0) >= COALESCE(so.AMOUNT, 0) THEN 'Paid'
                WHEN COALESCE(rpr.PAID_AMOUNT, 0) > 0 THEN 'Reserved/Partially Paid'
                WHEN so.STATUS IN ('Complete', 'Finalized')
                        AND COALESCE(so.AMOUNT, 0) <= 0 THEN 'Paid'
                WHEN so.STATUS IN ('Complete', 'Finalized', 'Confirmed') THEN 'Signed Contract'
                WHEN so.STATUS = 'Tentative' THEN 'Proposal/Negotiation'
                WHEN so.STATUS = 'Pending' THEN 'Inquiry'
                WHEN so.STATUS IN ('Reserved', 'Unresolved') THEN 'Reserved/Partially Paid'
                ELSE 'Inquiry'
        END) = 'Reserved' THEN 17 WHEN (CASE
                WHEN so.STATUS = 'Cancelled' THEN 'Canceled'
                WHEN COALESCE(rpr.PAID_AMOUNT, 0) > 0
                        AND COALESCE(rpr.PAID_AMOUNT, 0) >= COALESCE(so.AMOUNT, 0) THEN 'Paid'
                WHEN COALESCE(rpr.PAID_AMOUNT, 0) > 0 THEN 'Reserved/Partially Paid'
                WHEN so.STATUS IN ('Complete', 'Finalized')
                        AND COALESCE(so.AMOUNT, 0) <= 0 THEN 'Paid'
                WHEN so.STATUS IN ('Complete', 'Finalized', 'Confirmed') THEN 'Signed Contract'
                WHEN so.STATUS = 'Tentative' THEN 'Proposal/Negotiation'
                WHEN so.STATUS = 'Pending' THEN 'Inquiry'
                WHEN so.STATUS IN ('Reserved', 'Unresolved') THEN 'Reserved/Partially Paid'
                ELSE 'Inquiry'
        END) = 'Unresolved' THEN 18 ELSE 99 END AS rr_post, CASE WHEN (CASE
                WHEN r.ID IS NOT NULL AND so.STATUS = 'Cancelled' THEN 'Canceled'
                WHEN r.ID IS NOT NULL
                        AND COALESCE(rpr.PAID_AMOUNT, 0) > 0
                        AND COALESCE(rpr.PAID_AMOUNT, 0) >= COALESCE(so.AMOUNT, 0) THEN 'Sold'
                WHEN r.ID IS NOT NULL AND COALESCE(rpr.PAID_AMOUNT, 0) > 0 THEN 'Reserved'
                WHEN r.ID IS NOT NULL AND so.STATUS IN ('Complete', 'Finalized')
                        AND COALESCE(so.AMOUNT, 0) <= 0 THEN 'Sold'
                WHEN r.ID IS NOT NULL AND so.STATUS IN ('Complete', 'Finalized', 'Confirmed') THEN 'Reserved'
                WHEN r.ID IS NOT NULL AND so.STATUS = 'Tentative' THEN 'Reserved'
                WHEN r.ID IS NOT NULL AND so.STATUS = 'Pending' THEN 'Pending'
                WHEN r.ID IS NOT NULL AND so.STATUS IN ('Reserved', 'Unresolved') THEN 'Reserved'
                WHEN r.ID IS NOT NULL THEN 'Pending'
                
                WHEN so.STATUS = 'Complete' THEN 'Sold'
                WHEN so.STATUS = 'Pending' THEN 'Pending'
                WHEN so.STATUS = 'Cancelled' THEN 'Canceled'
                WHEN so.STATUS = 'Unresolved' THEN 'Pending'
                WHEN so.STATUS = 'Tentative' OR so.STATUSCODE = 2 THEN 'Reserved'
                ELSE so.STATUS
        END) IS NULL THEN 0 WHEN (CASE
                WHEN r.ID IS NOT NULL AND so.STATUS = 'Cancelled' THEN 'Canceled'
                WHEN r.ID IS NOT NULL
                        AND COALESCE(rpr.PAID_AMOUNT, 0) > 0
                        AND COALESCE(rpr.PAID_AMOUNT, 0) >= COALESCE(so.AMOUNT, 0) THEN 'Sold'
                WHEN r.ID IS NOT NULL AND COALESCE(rpr.PAID_AMOUNT, 0) > 0 THEN 'Reserved'
                WHEN r.ID IS NOT NULL AND so.STATUS IN ('Complete', 'Finalized')
                        AND COALESCE(so.AMOUNT, 0) <= 0 THEN 'Sold'
                WHEN r.ID IS NOT NULL AND so.STATUS IN ('Complete', 'Finalized', 'Confirmed') THEN 'Reserved'
                WHEN r.ID IS NOT NULL AND so.STATUS = 'Tentative' THEN 'Reserved'
                WHEN r.ID IS NOT NULL AND so.STATUS = 'Pending' THEN 'Pending'
                WHEN r.ID IS NOT NULL AND so.STATUS IN ('Reserved', 'Unresolved') THEN 'Reserved'
                WHEN r.ID IS NOT NULL THEN 'Pending'
                
                WHEN so.STATUS = 'Complete' THEN 'Sold'
                WHEN so.STATUS = 'Pending' THEN 'Pending'
                WHEN so.STATUS = 'Cancelled' THEN 'Canceled'
                WHEN so.STATUS = 'Unresolved' THEN 'Pending'
                WHEN so.STATUS = 'Tentative' OR so.STATUSCODE = 2 THEN 'Reserved'
                ELSE so.STATUS
        END) = 'Canceled' THEN 21 WHEN (CASE
                WHEN r.ID IS NOT NULL AND so.STATUS = 'Cancelled' THEN 'Canceled'
                WHEN r.ID IS NOT NULL
                        AND COALESCE(rpr.PAID_AMOUNT, 0) > 0
                        AND COALESCE(rpr.PAID_AMOUNT, 0) >= COALESCE(so.AMOUNT, 0) THEN 'Sold'
                WHEN r.ID IS NOT NULL AND COALESCE(rpr.PAID_AMOUNT, 0) > 0 THEN 'Reserved'
                WHEN r.ID IS NOT NULL AND so.STATUS IN ('Complete', 'Finalized')
                        AND COALESCE(so.AMOUNT, 0) <= 0 THEN 'Sold'
                WHEN r.ID IS NOT NULL AND so.STATUS IN ('Complete', 'Finalized', 'Confirmed') THEN 'Reserved'
                WHEN r.ID IS NOT NULL AND so.STATUS = 'Tentative' THEN 'Reserved'
                WHEN r.ID IS NOT NULL AND so.STATUS = 'Pending' THEN 'Pending'
                WHEN r.ID IS NOT NULL AND so.STATUS IN ('Reserved', 'Unresolved') THEN 'Reserved'
                WHEN r.ID IS NOT NULL THEN 'Pending'
                
                WHEN so.STATUS = 'Complete' THEN 'Sold'
                WHEN so.STATUS = 'Pending' THEN 'Pending'
                WHEN so.STATUS = 'Cancelled' THEN 'Canceled'
                WHEN so.STATUS = 'Unresolved' THEN 'Pending'
                WHEN so.STATUS = 'Tentative' OR so.STATUSCODE = 2 THEN 'Reserved'
                ELSE so.STATUS
        END) = 'Sold' THEN 22 WHEN (CASE
                WHEN r.ID IS NOT NULL AND so.STATUS = 'Cancelled' THEN 'Canceled'
                WHEN r.ID IS NOT NULL
                        AND COALESCE(rpr.PAID_AMOUNT, 0) > 0
                        AND COALESCE(rpr.PAID_AMOUNT, 0) >= COALESCE(so.AMOUNT, 0) THEN 'Sold'
                WHEN r.ID IS NOT NULL AND COALESCE(rpr.PAID_AMOUNT, 0) > 0 THEN 'Reserved'
                WHEN r.ID IS NOT NULL AND so.STATUS IN ('Complete', 'Finalized')
                        AND COALESCE(so.AMOUNT, 0) <= 0 THEN 'Sold'
                WHEN r.ID IS NOT NULL AND so.STATUS IN ('Complete', 'Finalized', 'Confirmed') THEN 'Reserved'
                WHEN r.ID IS NOT NULL AND so.STATUS = 'Tentative' THEN 'Reserved'
                WHEN r.ID IS NOT NULL AND so.STATUS = 'Pending' THEN 'Pending'
                WHEN r.ID IS NOT NULL AND so.STATUS IN ('Reserved', 'Unresolved') THEN 'Reserved'
                WHEN r.ID IS NOT NULL THEN 'Pending'
                
                WHEN so.STATUS = 'Complete' THEN 'Sold'
                WHEN so.STATUS = 'Pending' THEN 'Pending'
                WHEN so.STATUS = 'Cancelled' THEN 'Canceled'
                WHEN so.STATUS = 'Unresolved' THEN 'Pending'
                WHEN so.STATUS = 'Tentative' OR so.STATUSCODE = 2 THEN 'Reserved'
                ELSE so.STATUS
        END) = 'Reserved' THEN 23 WHEN (CASE
                WHEN r.ID IS NOT NULL AND so.STATUS = 'Cancelled' THEN 'Canceled'
                WHEN r.ID IS NOT NULL
                        AND COALESCE(rpr.PAID_AMOUNT, 0) > 0
                        AND COALESCE(rpr.PAID_AMOUNT, 0) >= COALESCE(so.AMOUNT, 0) THEN 'Sold'
                WHEN r.ID IS NOT NULL AND COALESCE(rpr.PAID_AMOUNT, 0) > 0 THEN 'Reserved'
                WHEN r.ID IS NOT NULL AND so.STATUS IN ('Complete', 'Finalized')
                        AND COALESCE(so.AMOUNT, 0) <= 0 THEN 'Sold'
                WHEN r.ID IS NOT NULL AND so.STATUS IN ('Complete', 'Finalized', 'Confirmed') THEN 'Reserved'
                WHEN r.ID IS NOT NULL AND so.STATUS = 'Tentative' THEN 'Reserved'
                WHEN r.ID IS NOT NULL AND so.STATUS = 'Pending' THEN 'Pending'
                WHEN r.ID IS NOT NULL AND so.STATUS IN ('Reserved', 'Unresolved') THEN 'Reserved'
                WHEN r.ID IS NOT NULL THEN 'Pending'
                
                WHEN so.STATUS = 'Complete' THEN 'Sold'
                WHEN so.STATUS = 'Pending' THEN 'Pending'
                WHEN so.STATUS = 'Cancelled' THEN 'Canceled'
                WHEN so.STATUS = 'Unresolved' THEN 'Pending'
                WHEN so.STATUS = 'Tentative' OR so.STATUSCODE = 2 THEN 'Reserved'
                ELSE so.STATUS
        END) = 'Pending' THEN 24 WHEN (CASE
                WHEN r.ID IS NOT NULL AND so.STATUS = 'Cancelled' THEN 'Canceled'
                WHEN r.ID IS NOT NULL
                        AND COALESCE(rpr.PAID_AMOUNT, 0) > 0
                        AND COALESCE(rpr.PAID_AMOUNT, 0) >= COALESCE(so.AMOUNT, 0) THEN 'Sold'
                WHEN r.ID IS NOT NULL AND COALESCE(rpr.PAID_AMOUNT, 0) > 0 THEN 'Reserved'
                WHEN r.ID IS NOT NULL AND so.STATUS IN ('Complete', 'Finalized')
                        AND COALESCE(so.AMOUNT, 0) <= 0 THEN 'Sold'
                WHEN r.ID IS NOT NULL AND so.STATUS IN ('Complete', 'Finalized', 'Confirmed') THEN 'Reserved'
                WHEN r.ID IS NOT NULL AND so.STATUS = 'Tentative' THEN 'Reserved'
                WHEN r.ID IS NOT NULL AND so.STATUS = 'Pending' THEN 'Pending'
                WHEN r.ID IS NOT NULL AND so.STATUS IN ('Reserved', 'Unresolved') THEN 'Reserved'
                WHEN r.ID IS NOT NULL THEN 'Pending'
                
                WHEN so.STATUS = 'Complete' THEN 'Sold'
                WHEN so.STATUS = 'Pending' THEN 'Pending'
                WHEN so.STATUS = 'Cancelled' THEN 'Canceled'
                WHEN so.STATUS = 'Unresolved' THEN 'Pending'
                WHEN so.STATUS = 'Tentative' OR so.STATUSCODE = 2 THEN 'Reserved'
                ELSE so.STATUS
        END) = 'Confirmed' THEN 25 WHEN (CASE
                WHEN r.ID IS NOT NULL AND so.STATUS = 'Cancelled' THEN 'Canceled'
                WHEN r.ID IS NOT NULL
                        AND COALESCE(rpr.PAID_AMOUNT, 0) > 0
                        AND COALESCE(rpr.PAID_AMOUNT, 0) >= COALESCE(so.AMOUNT, 0) THEN 'Sold'
                WHEN r.ID IS NOT NULL AND COALESCE(rpr.PAID_AMOUNT, 0) > 0 THEN 'Reserved'
                WHEN r.ID IS NOT NULL AND so.STATUS IN ('Complete', 'Finalized')
                        AND COALESCE(so.AMOUNT, 0) <= 0 THEN 'Sold'
                WHEN r.ID IS NOT NULL AND so.STATUS IN ('Complete', 'Finalized', 'Confirmed') THEN 'Reserved'
                WHEN r.ID IS NOT NULL AND so.STATUS = 'Tentative' THEN 'Reserved'
                WHEN r.ID IS NOT NULL AND so.STATUS = 'Pending' THEN 'Pending'
                WHEN r.ID IS NOT NULL AND so.STATUS IN ('Reserved', 'Unresolved') THEN 'Reserved'
                WHEN r.ID IS NOT NULL THEN 'Pending'
                
                WHEN so.STATUS = 'Complete' THEN 'Sold'
                WHEN so.STATUS = 'Pending' THEN 'Pending'
                WHEN so.STATUS = 'Cancelled' THEN 'Canceled'
                WHEN so.STATUS = 'Unresolved' THEN 'Pending'
                WHEN so.STATUS = 'Tentative' OR so.STATUSCODE = 2 THEN 'Reserved'
                ELSE so.STATUS
        END) = 'Finalized' THEN 26 WHEN (CASE
                WHEN r.ID IS NOT NULL AND so.STATUS = 'Cancelled' THEN 'Canceled'
                WHEN r.ID IS NOT NULL
                        AND COALESCE(rpr.PAID_AMOUNT, 0) > 0
                        AND COALESCE(rpr.PAID_AMOUNT, 0) >= COALESCE(so.AMOUNT, 0) THEN 'Sold'
                WHEN r.ID IS NOT NULL AND COALESCE(rpr.PAID_AMOUNT, 0) > 0 THEN 'Reserved'
                WHEN r.ID IS NOT NULL AND so.STATUS IN ('Complete', 'Finalized')
                        AND COALESCE(so.AMOUNT, 0) <= 0 THEN 'Sold'
                WHEN r.ID IS NOT NULL AND so.STATUS IN ('Complete', 'Finalized', 'Confirmed') THEN 'Reserved'
                WHEN r.ID IS NOT NULL AND so.STATUS = 'Tentative' THEN 'Reserved'
                WHEN r.ID IS NOT NULL AND so.STATUS = 'Pending' THEN 'Pending'
                WHEN r.ID IS NOT NULL AND so.STATUS IN ('Reserved', 'Unresolved') THEN 'Reserved'
                WHEN r.ID IS NOT NULL THEN 'Pending'
                
                WHEN so.STATUS = 'Complete' THEN 'Sold'
                WHEN so.STATUS = 'Pending' THEN 'Pending'
                WHEN so.STATUS = 'Cancelled' THEN 'Canceled'
                WHEN so.STATUS = 'Unresolved' THEN 'Pending'
                WHEN so.STATUS = 'Tentative' OR so.STATUSCODE = 2 THEN 'Reserved'
                ELSE so.STATUS
        END) = 'Complete' THEN 27 WHEN (CASE
                WHEN r.ID IS NOT NULL AND so.STATUS = 'Cancelled' THEN 'Canceled'
                WHEN r.ID IS NOT NULL
                        AND COALESCE(rpr.PAID_AMOUNT, 0) > 0
                        AND COALESCE(rpr.PAID_AMOUNT, 0) >= COALESCE(so.AMOUNT, 0) THEN 'Sold'
                WHEN r.ID IS NOT NULL AND COALESCE(rpr.PAID_AMOUNT, 0) > 0 THEN 'Reserved'
                WHEN r.ID IS NOT NULL AND so.STATUS IN ('Complete', 'Finalized')
                        AND COALESCE(so.AMOUNT, 0) <= 0 THEN 'Sold'
                WHEN r.ID IS NOT NULL AND so.STATUS IN ('Complete', 'Finalized', 'Confirmed') THEN 'Reserved'
                WHEN r.ID IS NOT NULL AND so.STATUS = 'Tentative' THEN 'Reserved'
                WHEN r.ID IS NOT NULL AND so.STATUS = 'Pending' THEN 'Pending'
                WHEN r.ID IS NOT NULL AND so.STATUS IN ('Reserved', 'Unresolved') THEN 'Reserved'
                WHEN r.ID IS NOT NULL THEN 'Pending'
                
                WHEN so.STATUS = 'Complete' THEN 'Sold'
                WHEN so.STATUS = 'Pending' THEN 'Pending'
                WHEN so.STATUS = 'Cancelled' THEN 'Canceled'
                WHEN so.STATUS = 'Unresolved' THEN 'Pending'
                WHEN so.STATUS = 'Tentative' OR so.STATUSCODE = 2 THEN 'Reserved'
                ELSE so.STATUS
        END) = 'Tentative' THEN 28 WHEN (CASE
                WHEN r.ID IS NOT NULL AND so.STATUS = 'Cancelled' THEN 'Canceled'
                WHEN r.ID IS NOT NULL
                        AND COALESCE(rpr.PAID_AMOUNT, 0) > 0
                        AND COALESCE(rpr.PAID_AMOUNT, 0) >= COALESCE(so.AMOUNT, 0) THEN 'Sold'
                WHEN r.ID IS NOT NULL AND COALESCE(rpr.PAID_AMOUNT, 0) > 0 THEN 'Reserved'
                WHEN r.ID IS NOT NULL AND so.STATUS IN ('Complete', 'Finalized')
                        AND COALESCE(so.AMOUNT, 0) <= 0 THEN 'Sold'
                WHEN r.ID IS NOT NULL AND so.STATUS IN ('Complete', 'Finalized', 'Confirmed') THEN 'Reserved'
                WHEN r.ID IS NOT NULL AND so.STATUS = 'Tentative' THEN 'Reserved'
                WHEN r.ID IS NOT NULL AND so.STATUS = 'Pending' THEN 'Pending'
                WHEN r.ID IS NOT NULL AND so.STATUS IN ('Reserved', 'Unresolved') THEN 'Reserved'
                WHEN r.ID IS NOT NULL THEN 'Pending'
                
                WHEN so.STATUS = 'Complete' THEN 'Sold'
                WHEN so.STATUS = 'Pending' THEN 'Pending'
                WHEN so.STATUS = 'Cancelled' THEN 'Canceled'
                WHEN so.STATUS = 'Unresolved' THEN 'Pending'
                WHEN so.STATUS = 'Tentative' OR so.STATUSCODE = 2 THEN 'Reserved'
                ELSE so.STATUS
        END) = 'Unresolved' THEN 29 WHEN (CASE
                WHEN r.ID IS NOT NULL AND so.STATUS = 'Cancelled' THEN 'Canceled'
                WHEN r.ID IS NOT NULL
                        AND COALESCE(rpr.PAID_AMOUNT, 0) > 0
                        AND COALESCE(rpr.PAID_AMOUNT, 0) >= COALESCE(so.AMOUNT, 0) THEN 'Sold'
                WHEN r.ID IS NOT NULL AND COALESCE(rpr.PAID_AMOUNT, 0) > 0 THEN 'Reserved'
                WHEN r.ID IS NOT NULL AND so.STATUS IN ('Complete', 'Finalized')
                        AND COALESCE(so.AMOUNT, 0) <= 0 THEN 'Sold'
                WHEN r.ID IS NOT NULL AND so.STATUS IN ('Complete', 'Finalized', 'Confirmed') THEN 'Reserved'
                WHEN r.ID IS NOT NULL AND so.STATUS = 'Tentative' THEN 'Reserved'
                WHEN r.ID IS NOT NULL AND so.STATUS = 'Pending' THEN 'Pending'
                WHEN r.ID IS NOT NULL AND so.STATUS IN ('Reserved', 'Unresolved') THEN 'Reserved'
                WHEN r.ID IS NOT NULL THEN 'Pending'
                
                WHEN so.STATUS = 'Complete' THEN 'Sold'
                WHEN so.STATUS = 'Pending' THEN 'Pending'
                WHEN so.STATUS = 'Cancelled' THEN 'Canceled'
                WHEN so.STATUS = 'Unresolved' THEN 'Pending'
                WHEN so.STATUS = 'Tentative' OR so.STATUSCODE = 2 THEN 'Reserved'
                ELSE so.STATUS
        END) = 'Cancelled' THEN 30 WHEN (CASE
                WHEN r.ID IS NOT NULL AND so.STATUS = 'Cancelled' THEN 'Canceled'
                WHEN r.ID IS NOT NULL
                        AND COALESCE(rpr.PAID_AMOUNT, 0) > 0
                        AND COALESCE(rpr.PAID_AMOUNT, 0) >= COALESCE(so.AMOUNT, 0) THEN 'Sold'
                WHEN r.ID IS NOT NULL AND COALESCE(rpr.PAID_AMOUNT, 0) > 0 THEN 'Reserved'
                WHEN r.ID IS NOT NULL AND so.STATUS IN ('Complete', 'Finalized')
                        AND COALESCE(so.AMOUNT, 0) <= 0 THEN 'Sold'
                WHEN r.ID IS NOT NULL AND so.STATUS IN ('Complete', 'Finalized', 'Confirmed') THEN 'Reserved'
                WHEN r.ID IS NOT NULL AND so.STATUS = 'Tentative' THEN 'Reserved'
                WHEN r.ID IS NOT NULL AND so.STATUS = 'Pending' THEN 'Pending'
                WHEN r.ID IS NOT NULL AND so.STATUS IN ('Reserved', 'Unresolved') THEN 'Reserved'
                WHEN r.ID IS NOT NULL THEN 'Pending'
                
                WHEN so.STATUS = 'Complete' THEN 'Sold'
                WHEN so.STATUS = 'Pending' THEN 'Pending'
                WHEN so.STATUS = 'Cancelled' THEN 'Canceled'
                WHEN so.STATUS = 'Unresolved' THEN 'Pending'
                WHEN so.STATUS = 'Tentative' OR so.STATUSCODE = 2 THEN 'Reserved'
                ELSE so.STATUS
        END) = 'Refunded' THEN 31 ELSE 99 END AS tk_post_res, CASE WHEN (CASE
                WHEN r0.ID IS NOT NULL AND so.STATUS = 'Cancelled' THEN 'Canceled'
                WHEN r0.ID IS NOT NULL
                        AND COALESCE(rpr.PAID_AMOUNT, 0) > 0
                        AND COALESCE(rpr.PAID_AMOUNT, 0) >= COALESCE(so.AMOUNT, 0) THEN 'Sold'
                WHEN r0.ID IS NOT NULL AND COALESCE(rpr.PAID_AMOUNT, 0) > 0 THEN 'Reserved'
                WHEN r0.ID IS NOT NULL AND so.STATUS IN ('Complete', 'Finalized')
                        AND COALESCE(so.AMOUNT, 0) <= 0 THEN 'Sold'
                WHEN r0.ID IS NOT NULL AND so.STATUS IN ('Complete', 'Finalized', 'Confirmed') THEN 'Reserved'
                WHEN r0.ID IS NOT NULL AND so.STATUS = 'Tentative' THEN 'Reserved'
                WHEN r0.ID IS NOT NULL AND so.STATUS = 'Pending' THEN 'Pending'
                WHEN r0.ID IS NOT NULL AND so.STATUS IN ('Reserved', 'Unresolved') THEN 'Reserved'
                WHEN r0.ID IS NOT NULL THEN 'Pending'
                
                WHEN so.STATUS = 'Complete' THEN 'Sold'
                WHEN so.STATUS = 'Pending' THEN 'Pending'
                WHEN so.STATUS = 'Cancelled' THEN 'Canceled'
                WHEN so.STATUS = 'Unresolved' THEN 'Pending'
                WHEN so.STATUS = 'Tentative' OR so.STATUSCODE = 2 THEN 'Reserved'
                ELSE so.STATUS
        END) IS NULL THEN 0 WHEN (CASE
                WHEN r0.ID IS NOT NULL AND so.STATUS = 'Cancelled' THEN 'Canceled'
                WHEN r0.ID IS NOT NULL
                        AND COALESCE(rpr.PAID_AMOUNT, 0) > 0
                        AND COALESCE(rpr.PAID_AMOUNT, 0) >= COALESCE(so.AMOUNT, 0) THEN 'Sold'
                WHEN r0.ID IS NOT NULL AND COALESCE(rpr.PAID_AMOUNT, 0) > 0 THEN 'Reserved'
                WHEN r0.ID IS NOT NULL AND so.STATUS IN ('Complete', 'Finalized')
                        AND COALESCE(so.AMOUNT, 0) <= 0 THEN 'Sold'
                WHEN r0.ID IS NOT NULL AND so.STATUS IN ('Complete', 'Finalized', 'Confirmed') THEN 'Reserved'
                WHEN r0.ID IS NOT NULL AND so.STATUS = 'Tentative' THEN 'Reserved'
                WHEN r0.ID IS NOT NULL AND so.STATUS = 'Pending' THEN 'Pending'
                WHEN r0.ID IS NOT NULL AND so.STATUS IN ('Reserved', 'Unresolved') THEN 'Reserved'
                WHEN r0.ID IS NOT NULL THEN 'Pending'
                
                WHEN so.STATUS = 'Complete' THEN 'Sold'
                WHEN so.STATUS = 'Pending' THEN 'Pending'
                WHEN so.STATUS = 'Cancelled' THEN 'Canceled'
                WHEN so.STATUS = 'Unresolved' THEN 'Pending'
                WHEN so.STATUS = 'Tentative' OR so.STATUSCODE = 2 THEN 'Reserved'
                ELSE so.STATUS
        END) = 'Canceled' THEN 21 WHEN (CASE
                WHEN r0.ID IS NOT NULL AND so.STATUS = 'Cancelled' THEN 'Canceled'
                WHEN r0.ID IS NOT NULL
                        AND COALESCE(rpr.PAID_AMOUNT, 0) > 0
                        AND COALESCE(rpr.PAID_AMOUNT, 0) >= COALESCE(so.AMOUNT, 0) THEN 'Sold'
                WHEN r0.ID IS NOT NULL AND COALESCE(rpr.PAID_AMOUNT, 0) > 0 THEN 'Reserved'
                WHEN r0.ID IS NOT NULL AND so.STATUS IN ('Complete', 'Finalized')
                        AND COALESCE(so.AMOUNT, 0) <= 0 THEN 'Sold'
                WHEN r0.ID IS NOT NULL AND so.STATUS IN ('Complete', 'Finalized', 'Confirmed') THEN 'Reserved'
                WHEN r0.ID IS NOT NULL AND so.STATUS = 'Tentative' THEN 'Reserved'
                WHEN r0.ID IS NOT NULL AND so.STATUS = 'Pending' THEN 'Pending'
                WHEN r0.ID IS NOT NULL AND so.STATUS IN ('Reserved', 'Unresolved') THEN 'Reserved'
                WHEN r0.ID IS NOT NULL THEN 'Pending'
                
                WHEN so.STATUS = 'Complete' THEN 'Sold'
                WHEN so.STATUS = 'Pending' THEN 'Pending'
                WHEN so.STATUS = 'Cancelled' THEN 'Canceled'
                WHEN so.STATUS = 'Unresolved' THEN 'Pending'
                WHEN so.STATUS = 'Tentative' OR so.STATUSCODE = 2 THEN 'Reserved'
                ELSE so.STATUS
        END) = 'Sold' THEN 22 WHEN (CASE
                WHEN r0.ID IS NOT NULL AND so.STATUS = 'Cancelled' THEN 'Canceled'
                WHEN r0.ID IS NOT NULL
                        AND COALESCE(rpr.PAID_AMOUNT, 0) > 0
                        AND COALESCE(rpr.PAID_AMOUNT, 0) >= COALESCE(so.AMOUNT, 0) THEN 'Sold'
                WHEN r0.ID IS NOT NULL AND COALESCE(rpr.PAID_AMOUNT, 0) > 0 THEN 'Reserved'
                WHEN r0.ID IS NOT NULL AND so.STATUS IN ('Complete', 'Finalized')
                        AND COALESCE(so.AMOUNT, 0) <= 0 THEN 'Sold'
                WHEN r0.ID IS NOT NULL AND so.STATUS IN ('Complete', 'Finalized', 'Confirmed') THEN 'Reserved'
                WHEN r0.ID IS NOT NULL AND so.STATUS = 'Tentative' THEN 'Reserved'
                WHEN r0.ID IS NOT NULL AND so.STATUS = 'Pending' THEN 'Pending'
                WHEN r0.ID IS NOT NULL AND so.STATUS IN ('Reserved', 'Unresolved') THEN 'Reserved'
                WHEN r0.ID IS NOT NULL THEN 'Pending'
                
                WHEN so.STATUS = 'Complete' THEN 'Sold'
                WHEN so.STATUS = 'Pending' THEN 'Pending'
                WHEN so.STATUS = 'Cancelled' THEN 'Canceled'
                WHEN so.STATUS = 'Unresolved' THEN 'Pending'
                WHEN so.STATUS = 'Tentative' OR so.STATUSCODE = 2 THEN 'Reserved'
                ELSE so.STATUS
        END) = 'Reserved' THEN 23 WHEN (CASE
                WHEN r0.ID IS NOT NULL AND so.STATUS = 'Cancelled' THEN 'Canceled'
                WHEN r0.ID IS NOT NULL
                        AND COALESCE(rpr.PAID_AMOUNT, 0) > 0
                        AND COALESCE(rpr.PAID_AMOUNT, 0) >= COALESCE(so.AMOUNT, 0) THEN 'Sold'
                WHEN r0.ID IS NOT NULL AND COALESCE(rpr.PAID_AMOUNT, 0) > 0 THEN 'Reserved'
                WHEN r0.ID IS NOT NULL AND so.STATUS IN ('Complete', 'Finalized')
                        AND COALESCE(so.AMOUNT, 0) <= 0 THEN 'Sold'
                WHEN r0.ID IS NOT NULL AND so.STATUS IN ('Complete', 'Finalized', 'Confirmed') THEN 'Reserved'
                WHEN r0.ID IS NOT NULL AND so.STATUS = 'Tentative' THEN 'Reserved'
                WHEN r0.ID IS NOT NULL AND so.STATUS = 'Pending' THEN 'Pending'
                WHEN r0.ID IS NOT NULL AND so.STATUS IN ('Reserved', 'Unresolved') THEN 'Reserved'
                WHEN r0.ID IS NOT NULL THEN 'Pending'
                
                WHEN so.STATUS = 'Complete' THEN 'Sold'
                WHEN so.STATUS = 'Pending' THEN 'Pending'
                WHEN so.STATUS = 'Cancelled' THEN 'Canceled'
                WHEN so.STATUS = 'Unresolved' THEN 'Pending'
                WHEN so.STATUS = 'Tentative' OR so.STATUSCODE = 2 THEN 'Reserved'
                ELSE so.STATUS
        END) = 'Pending' THEN 24 WHEN (CASE
                WHEN r0.ID IS NOT NULL AND so.STATUS = 'Cancelled' THEN 'Canceled'
                WHEN r0.ID IS NOT NULL
                        AND COALESCE(rpr.PAID_AMOUNT, 0) > 0
                        AND COALESCE(rpr.PAID_AMOUNT, 0) >= COALESCE(so.AMOUNT, 0) THEN 'Sold'
                WHEN r0.ID IS NOT NULL AND COALESCE(rpr.PAID_AMOUNT, 0) > 0 THEN 'Reserved'
                WHEN r0.ID IS NOT NULL AND so.STATUS IN ('Complete', 'Finalized')
                        AND COALESCE(so.AMOUNT, 0) <= 0 THEN 'Sold'
                WHEN r0.ID IS NOT NULL AND so.STATUS IN ('Complete', 'Finalized', 'Confirmed') THEN 'Reserved'
                WHEN r0.ID IS NOT NULL AND so.STATUS = 'Tentative' THEN 'Reserved'
                WHEN r0.ID IS NOT NULL AND so.STATUS = 'Pending' THEN 'Pending'
                WHEN r0.ID IS NOT NULL AND so.STATUS IN ('Reserved', 'Unresolved') THEN 'Reserved'
                WHEN r0.ID IS NOT NULL THEN 'Pending'
                
                WHEN so.STATUS = 'Complete' THEN 'Sold'
                WHEN so.STATUS = 'Pending' THEN 'Pending'
                WHEN so.STATUS = 'Cancelled' THEN 'Canceled'
                WHEN so.STATUS = 'Unresolved' THEN 'Pending'
                WHEN so.STATUS = 'Tentative' OR so.STATUSCODE = 2 THEN 'Reserved'
                ELSE so.STATUS
        END) = 'Confirmed' THEN 25 WHEN (CASE
                WHEN r0.ID IS NOT NULL AND so.STATUS = 'Cancelled' THEN 'Canceled'
                WHEN r0.ID IS NOT NULL
                        AND COALESCE(rpr.PAID_AMOUNT, 0) > 0
                        AND COALESCE(rpr.PAID_AMOUNT, 0) >= COALESCE(so.AMOUNT, 0) THEN 'Sold'
                WHEN r0.ID IS NOT NULL AND COALESCE(rpr.PAID_AMOUNT, 0) > 0 THEN 'Reserved'
                WHEN r0.ID IS NOT NULL AND so.STATUS IN ('Complete', 'Finalized')
                        AND COALESCE(so.AMOUNT, 0) <= 0 THEN 'Sold'
                WHEN r0.ID IS NOT NULL AND so.STATUS IN ('Complete', 'Finalized', 'Confirmed') THEN 'Reserved'
                WHEN r0.ID IS NOT NULL AND so.STATUS = 'Tentative' THEN 'Reserved'
                WHEN r0.ID IS NOT NULL AND so.STATUS = 'Pending' THEN 'Pending'
                WHEN r0.ID IS NOT NULL AND so.STATUS IN ('Reserved', 'Unresolved') THEN 'Reserved'
                WHEN r0.ID IS NOT NULL THEN 'Pending'
                
                WHEN so.STATUS = 'Complete' THEN 'Sold'
                WHEN so.STATUS = 'Pending' THEN 'Pending'
                WHEN so.STATUS = 'Cancelled' THEN 'Canceled'
                WHEN so.STATUS = 'Unresolved' THEN 'Pending'
                WHEN so.STATUS = 'Tentative' OR so.STATUSCODE = 2 THEN 'Reserved'
                ELSE so.STATUS
        END) = 'Finalized' THEN 26 WHEN (CASE
                WHEN r0.ID IS NOT NULL AND so.STATUS = 'Cancelled' THEN 'Canceled'
                WHEN r0.ID IS NOT NULL
                        AND COALESCE(rpr.PAID_AMOUNT, 0) > 0
                        AND COALESCE(rpr.PAID_AMOUNT, 0) >= COALESCE(so.AMOUNT, 0) THEN 'Sold'
                WHEN r0.ID IS NOT NULL AND COALESCE(rpr.PAID_AMOUNT, 0) > 0 THEN 'Reserved'
                WHEN r0.ID IS NOT NULL AND so.STATUS IN ('Complete', 'Finalized')
                        AND COALESCE(so.AMOUNT, 0) <= 0 THEN 'Sold'
                WHEN r0.ID IS NOT NULL AND so.STATUS IN ('Complete', 'Finalized', 'Confirmed') THEN 'Reserved'
                WHEN r0.ID IS NOT NULL AND so.STATUS = 'Tentative' THEN 'Reserved'
                WHEN r0.ID IS NOT NULL AND so.STATUS = 'Pending' THEN 'Pending'
                WHEN r0.ID IS NOT NULL AND so.STATUS IN ('Reserved', 'Unresolved') THEN 'Reserved'
                WHEN r0.ID IS NOT NULL THEN 'Pending'
                
                WHEN so.STATUS = 'Complete' THEN 'Sold'
                WHEN so.STATUS = 'Pending' THEN 'Pending'
                WHEN so.STATUS = 'Cancelled' THEN 'Canceled'
                WHEN so.STATUS = 'Unresolved' THEN 'Pending'
                WHEN so.STATUS = 'Tentative' OR so.STATUSCODE = 2 THEN 'Reserved'
                ELSE so.STATUS
        END) = 'Complete' THEN 27 WHEN (CASE
                WHEN r0.ID IS NOT NULL AND so.STATUS = 'Cancelled' THEN 'Canceled'
                WHEN r0.ID IS NOT NULL
                        AND COALESCE(rpr.PAID_AMOUNT, 0) > 0
                        AND COALESCE(rpr.PAID_AMOUNT, 0) >= COALESCE(so.AMOUNT, 0) THEN 'Sold'
                WHEN r0.ID IS NOT NULL AND COALESCE(rpr.PAID_AMOUNT, 0) > 0 THEN 'Reserved'
                WHEN r0.ID IS NOT NULL AND so.STATUS IN ('Complete', 'Finalized')
                        AND COALESCE(so.AMOUNT, 0) <= 0 THEN 'Sold'
                WHEN r0.ID IS NOT NULL AND so.STATUS IN ('Complete', 'Finalized', 'Confirmed') THEN 'Reserved'
                WHEN r0.ID IS NOT NULL AND so.STATUS = 'Tentative' THEN 'Reserved'
                WHEN r0.ID IS NOT NULL AND so.STATUS = 'Pending' THEN 'Pending'
                WHEN r0.ID IS NOT NULL AND so.STATUS IN ('Reserved', 'Unresolved') THEN 'Reserved'
                WHEN r0.ID IS NOT NULL THEN 'Pending'
                
                WHEN so.STATUS = 'Complete' THEN 'Sold'
                WHEN so.STATUS = 'Pending' THEN 'Pending'
                WHEN so.STATUS = 'Cancelled' THEN 'Canceled'
                WHEN so.STATUS = 'Unresolved' THEN 'Pending'
                WHEN so.STATUS = 'Tentative' OR so.STATUSCODE = 2 THEN 'Reserved'
                ELSE so.STATUS
        END) = 'Tentative' THEN 28 WHEN (CASE
                WHEN r0.ID IS NOT NULL AND so.STATUS = 'Cancelled' THEN 'Canceled'
                WHEN r0.ID IS NOT NULL
                        AND COALESCE(rpr.PAID_AMOUNT, 0) > 0
                        AND COALESCE(rpr.PAID_AMOUNT, 0) >= COALESCE(so.AMOUNT, 0) THEN 'Sold'
                WHEN r0.ID IS NOT NULL AND COALESCE(rpr.PAID_AMOUNT, 0) > 0 THEN 'Reserved'
                WHEN r0.ID IS NOT NULL AND so.STATUS IN ('Complete', 'Finalized')
                        AND COALESCE(so.AMOUNT, 0) <= 0 THEN 'Sold'
                WHEN r0.ID IS NOT NULL AND so.STATUS IN ('Complete', 'Finalized', 'Confirmed') THEN 'Reserved'
                WHEN r0.ID IS NOT NULL AND so.STATUS = 'Tentative' THEN 'Reserved'
                WHEN r0.ID IS NOT NULL AND so.STATUS = 'Pending' THEN 'Pending'
                WHEN r0.ID IS NOT NULL AND so.STATUS IN ('Reserved', 'Unresolved') THEN 'Reserved'
                WHEN r0.ID IS NOT NULL THEN 'Pending'
                
                WHEN so.STATUS = 'Complete' THEN 'Sold'
                WHEN so.STATUS = 'Pending' THEN 'Pending'
                WHEN so.STATUS = 'Cancelled' THEN 'Canceled'
                WHEN so.STATUS = 'Unresolved' THEN 'Pending'
                WHEN so.STATUS = 'Tentative' OR so.STATUSCODE = 2 THEN 'Reserved'
                ELSE so.STATUS
        END) = 'Unresolved' THEN 29 WHEN (CASE
                WHEN r0.ID IS NOT NULL AND so.STATUS = 'Cancelled' THEN 'Canceled'
                WHEN r0.ID IS NOT NULL
                        AND COALESCE(rpr.PAID_AMOUNT, 0) > 0
                        AND COALESCE(rpr.PAID_AMOUNT, 0) >= COALESCE(so.AMOUNT, 0) THEN 'Sold'
                WHEN r0.ID IS NOT NULL AND COALESCE(rpr.PAID_AMOUNT, 0) > 0 THEN 'Reserved'
                WHEN r0.ID IS NOT NULL AND so.STATUS IN ('Complete', 'Finalized')
                        AND COALESCE(so.AMOUNT, 0) <= 0 THEN 'Sold'
                WHEN r0.ID IS NOT NULL AND so.STATUS IN ('Complete', 'Finalized', 'Confirmed') THEN 'Reserved'
                WHEN r0.ID IS NOT NULL AND so.STATUS = 'Tentative' THEN 'Reserved'
                WHEN r0.ID IS NOT NULL AND so.STATUS = 'Pending' THEN 'Pending'
                WHEN r0.ID IS NOT NULL AND so.STATUS IN ('Reserved', 'Unresolved') THEN 'Reserved'
                WHEN r0.ID IS NOT NULL THEN 'Pending'
                
                WHEN so.STATUS = 'Complete' THEN 'Sold'
                WHEN so.STATUS = 'Pending' THEN 'Pending'
                WHEN so.STATUS = 'Cancelled' THEN 'Canceled'
                WHEN so.STATUS = 'Unresolved' THEN 'Pending'
                WHEN so.STATUS = 'Tentative' OR so.STATUSCODE = 2 THEN 'Reserved'
                ELSE so.STATUS
        END) = 'Cancelled' THEN 30 WHEN (CASE
                WHEN r0.ID IS NOT NULL AND so.STATUS = 'Cancelled' THEN 'Canceled'
                WHEN r0.ID IS NOT NULL
                        AND COALESCE(rpr.PAID_AMOUNT, 0) > 0
                        AND COALESCE(rpr.PAID_AMOUNT, 0) >= COALESCE(so.AMOUNT, 0) THEN 'Sold'
                WHEN r0.ID IS NOT NULL AND COALESCE(rpr.PAID_AMOUNT, 0) > 0 THEN 'Reserved'
                WHEN r0.ID IS NOT NULL AND so.STATUS IN ('Complete', 'Finalized')
                        AND COALESCE(so.AMOUNT, 0) <= 0 THEN 'Sold'
                WHEN r0.ID IS NOT NULL AND so.STATUS IN ('Complete', 'Finalized', 'Confirmed') THEN 'Reserved'
                WHEN r0.ID IS NOT NULL AND so.STATUS = 'Tentative' THEN 'Reserved'
                WHEN r0.ID IS NOT NULL AND so.STATUS = 'Pending' THEN 'Pending'
                WHEN r0.ID IS NOT NULL AND so.STATUS IN ('Reserved', 'Unresolved') THEN 'Reserved'
                WHEN r0.ID IS NOT NULL THEN 'Pending'
                
                WHEN so.STATUS = 'Complete' THEN 'Sold'
                WHEN so.STATUS = 'Pending' THEN 'Pending'
                WHEN so.STATUS = 'Cancelled' THEN 'Canceled'
                WHEN so.STATUS = 'Unresolved' THEN 'Pending'
                WHEN so.STATUS = 'Tentative' OR so.STATUSCODE = 2 THEN 'Reserved'
                ELSE so.STATUS
        END) = 'Refunded' THEN 31 ELSE 99 END AS tk_post_nonres, CASE WHEN (CASE
                WHEN so.STATUS = 'Complete' THEN 'Sold'
                WHEN so.STATUS = 'Pending' THEN 'Pending'
                WHEN so.STATUS = 'Cancelled' THEN 'Canceled'
                WHEN so.STATUS = 'Unresolved' THEN 'Pending'
                WHEN so.STATUS = 'Tentative' OR so.STATUSCODE = 2 THEN 'Reserved'
                ELSE so.STATUS
        END) IS NULL THEN 0 WHEN (CASE
                WHEN so.STATUS = 'Complete' THEN 'Sold'
                WHEN so.STATUS = 'Pending' THEN 'Pending'
                WHEN so.STATUS = 'Cancelled' THEN 'Canceled'
                WHEN so.STATUS = 'Unresolved' THEN 'Pending'
                WHEN so.STATUS = 'Tentative' OR so.STATUSCODE = 2 THEN 'Reserved'
                ELSE so.STATUS
        END) = 'Canceled' THEN 21 WHEN (CASE
                WHEN so.STATUS = 'Complete' THEN 'Sold'
                WHEN so.STATUS = 'Pending' THEN 'Pending'
                WHEN so.STATUS = 'Cancelled' THEN 'Canceled'
                WHEN so.STATUS = 'Unresolved' THEN 'Pending'
                WHEN so.STATUS = 'Tentative' OR so.STATUSCODE = 2 THEN 'Reserved'
                ELSE so.STATUS
        END) = 'Sold' THEN 22 WHEN (CASE
                WHEN so.STATUS = 'Complete' THEN 'Sold'
                WHEN so.STATUS = 'Pending' THEN 'Pending'
                WHEN so.STATUS = 'Cancelled' THEN 'Canceled'
                WHEN so.STATUS = 'Unresolved' THEN 'Pending'
                WHEN so.STATUS = 'Tentative' OR so.STATUSCODE = 2 THEN 'Reserved'
                ELSE so.STATUS
        END) = 'Reserved' THEN 23 WHEN (CASE
                WHEN so.STATUS = 'Complete' THEN 'Sold'
                WHEN so.STATUS = 'Pending' THEN 'Pending'
                WHEN so.STATUS = 'Cancelled' THEN 'Canceled'
                WHEN so.STATUS = 'Unresolved' THEN 'Pending'
                WHEN so.STATUS = 'Tentative' OR so.STATUSCODE = 2 THEN 'Reserved'
                ELSE so.STATUS
        END) = 'Pending' THEN 24 WHEN (CASE
                WHEN so.STATUS = 'Complete' THEN 'Sold'
                WHEN so.STATUS = 'Pending' THEN 'Pending'
                WHEN so.STATUS = 'Cancelled' THEN 'Canceled'
                WHEN so.STATUS = 'Unresolved' THEN 'Pending'
                WHEN so.STATUS = 'Tentative' OR so.STATUSCODE = 2 THEN 'Reserved'
                ELSE so.STATUS
        END) = 'Confirmed' THEN 25 WHEN (CASE
                WHEN so.STATUS = 'Complete' THEN 'Sold'
                WHEN so.STATUS = 'Pending' THEN 'Pending'
                WHEN so.STATUS = 'Cancelled' THEN 'Canceled'
                WHEN so.STATUS = 'Unresolved' THEN 'Pending'
                WHEN so.STATUS = 'Tentative' OR so.STATUSCODE = 2 THEN 'Reserved'
                ELSE so.STATUS
        END) = 'Finalized' THEN 26 WHEN (CASE
                WHEN so.STATUS = 'Complete' THEN 'Sold'
                WHEN so.STATUS = 'Pending' THEN 'Pending'
                WHEN so.STATUS = 'Cancelled' THEN 'Canceled'
                WHEN so.STATUS = 'Unresolved' THEN 'Pending'
                WHEN so.STATUS = 'Tentative' OR so.STATUSCODE = 2 THEN 'Reserved'
                ELSE so.STATUS
        END) = 'Complete' THEN 27 WHEN (CASE
                WHEN so.STATUS = 'Complete' THEN 'Sold'
                WHEN so.STATUS = 'Pending' THEN 'Pending'
                WHEN so.STATUS = 'Cancelled' THEN 'Canceled'
                WHEN so.STATUS = 'Unresolved' THEN 'Pending'
                WHEN so.STATUS = 'Tentative' OR so.STATUSCODE = 2 THEN 'Reserved'
                ELSE so.STATUS
        END) = 'Tentative' THEN 28 WHEN (CASE
                WHEN so.STATUS = 'Complete' THEN 'Sold'
                WHEN so.STATUS = 'Pending' THEN 'Pending'
                WHEN so.STATUS = 'Cancelled' THEN 'Canceled'
                WHEN so.STATUS = 'Unresolved' THEN 'Pending'
                WHEN so.STATUS = 'Tentative' OR so.STATUSCODE = 2 THEN 'Reserved'
                ELSE so.STATUS
        END) = 'Unresolved' THEN 29 WHEN (CASE
                WHEN so.STATUS = 'Complete' THEN 'Sold'
                WHEN so.STATUS = 'Pending' THEN 'Pending'
                WHEN so.STATUS = 'Cancelled' THEN 'Canceled'
                WHEN so.STATUS = 'Unresolved' THEN 'Pending'
                WHEN so.STATUS = 'Tentative' OR so.STATUSCODE = 2 THEN 'Reserved'
                ELSE so.STATUS
        END) = 'Cancelled' THEN 30 WHEN (CASE
                WHEN so.STATUS = 'Complete' THEN 'Sold'
                WHEN so.STATUS = 'Pending' THEN 'Pending'
                WHEN so.STATUS = 'Cancelled' THEN 'Canceled'
                WHEN so.STATUS = 'Unresolved' THEN 'Pending'
                WHEN so.STATUS = 'Tentative' OR so.STATUSCODE = 2 THEN 'Reserved'
                ELSE so.STATUS
        END) = 'Refunded' THEN 31 ELSE 99 END AS tk_pre_nonres
FROM (VALUES
  (1, 'Pending', 0, 100, NULL),
  (2, 'Pending', 0, 100, 0),
  (3, 'Pending', 0, 100, 40),
  (4, 'Pending', 0, 100, 100),
  (5, 'Pending', 0, 100, 150),
  (6, 'Pending', 0, 0, NULL),
  (7, 'Pending', 0, 0, 50),
  (8, 'Pending', 0, NULL, NULL),
  (9, 'Complete', 1, 100, NULL),
  (10, 'Complete', 1, 100, 0),
  (11, 'Complete', 1, 100, 40),
  (12, 'Complete', 1, 100, 100),
  (13, 'Complete', 1, 100, 150),
  (14, 'Complete', 1, 0, NULL),
  (15, 'Complete', 1, 0, 50),
  (16, 'Complete', 1, NULL, NULL),
  (17, 'Tentative', 2, 100, NULL),
  (18, 'Tentative', 2, 100, 0),
  (19, 'Tentative', 2, 100, 40),
  (20, 'Tentative', 2, 100, 100),
  (21, 'Tentative', 2, 100, 150),
  (22, 'Tentative', 2, 0, NULL),
  (23, 'Tentative', 2, 0, 50),
  (24, 'Tentative', 2, NULL, NULL),
  (25, 'Confirmed', 3, 100, NULL),
  (26, 'Confirmed', 3, 100, 0),
  (27, 'Confirmed', 3, 100, 40),
  (28, 'Confirmed', 3, 100, 100),
  (29, 'Confirmed', 3, 100, 150),
  (30, 'Confirmed', 3, 0, NULL),
  (31, 'Confirmed', 3, 0, 50),
  (32, 'Confirmed', 3, NULL, NULL),
  (33, 'Finalized', 4, 100, NULL),
  (34, 'Finalized', 4, 100, 0),
  (35, 'Finalized', 4, 100, 40),
  (36, 'Finalized', 4, 100, 100),
  (37, 'Finalized', 4, 100, 150),
  (38, 'Finalized', 4, 0, NULL),
  (39, 'Finalized', 4, 0, 50),
  (40, 'Finalized', 4, NULL, NULL),
  (41, 'Cancelled', 5, 100, NULL),
  (42, 'Cancelled', 5, 100, 0),
  (43, 'Cancelled', 5, 100, 40),
  (44, 'Cancelled', 5, 100, 100),
  (45, 'Cancelled', 5, 100, 150),
  (46, 'Cancelled', 5, 0, NULL),
  (47, 'Cancelled', 5, 0, 50),
  (48, 'Cancelled', 5, NULL, NULL),
  (49, 'Reserved', 6, 100, NULL),
  (50, 'Reserved', 6, 100, 0),
  (51, 'Reserved', 6, 100, 40),
  (52, 'Reserved', 6, 100, 100),
  (53, 'Reserved', 6, 100, 150),
  (54, 'Reserved', 6, 0, NULL),
  (55, 'Reserved', 6, 0, 50),
  (56, 'Reserved', 6, NULL, NULL),
  (57, 'Unresolved', 7, 100, NULL),
  (58, 'Unresolved', 7, 100, 0),
  (59, 'Unresolved', 7, 100, 40),
  (60, 'Unresolved', 7, 100, 100),
  (61, 'Unresolved', 7, 100, 150),
  (62, 'Unresolved', 7, 0, NULL),
  (63, 'Unresolved', 7, 0, 50),
  (64, 'Unresolved', 7, NULL, NULL)
) AS t(k, STATUS, STATUSCODE, AMOUNT, PAID)
CROSS APPLY (SELECT CAST(t.STATUS AS NVARCHAR(20)) AS STATUS, CAST(t.STATUSCODE AS TINYINT) AS STATUSCODE, CAST(t.AMOUNT AS MONEY) AS AMOUNT) so
CROSS APPLY (SELECT CAST(t.PAID AS MONEY) AS PAID_AMOUNT, CAST(t.PAID AS MONEY) AS NET_PAID_AMOUNT) rpr
CROSS APPLY (SELECT CAST('00000000-0000-0000-0000-000000000001' AS UNIQUEIDENTIFIER) AS ID) r
CROSS APPLY (SELECT CAST(NULL AS UNIQUEIDENTIFIER) AS ID) r0
ORDER BY t.k;
