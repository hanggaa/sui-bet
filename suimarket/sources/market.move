module suimarket::market {
    use sui::object::{Self, UID};
    use sui::balance::{Self, Balance, Supply};
    use sui::coin::{Self, Coin};
    use sui::sui::SUI;
    use sui::transfer;
    use sui::tx_context::{Self, TxContext};
    use std::string::{Self, String};

    // --- Error Codes ---
    const EMarketResolved: u64 = 0;
    const EIncorrectPayment: u64 = 1;
    const EInsufficientShares: u64 = 2;
    const EMarketNotResolved: u64 = 3;
    const EWrongOutcome: u64 = 4;
    const EInsufficientPoolFunds: u64 = 5;
    
    // --- Share Types ---
    public struct YES_SHARE has store, drop {}
    public struct NO_SHARE has store, drop {}

    // --- Objek Market & Portfolio ---
    public struct Market has key {
        id: UID,
        description: String,
        yes_share_supply: Supply<YES_SHARE>,
        no_share_supply: Supply<NO_SHARE>,
        pool: Balance<SUI>,
        is_resolved: bool,
        outcome: u8, // 0: unresolved, 1: YES, 2: NO
    }
    public struct Portfolio has key, store {
        id: UID,
        yes_shares: Balance<YES_SHARE>,
        no_shares: Balance<NO_SHARE>,
    }

    // --- Fungsi Create ---
    fun new(description: vector<u8>, ctx: &mut TxContext): Market {
        Market {
            id: object::new(ctx),
            description: string::utf8(description),
            yes_share_supply: balance::create_supply(YES_SHARE {}),
            no_share_supply: balance::create_supply(NO_SHARE {}),
            pool: balance::zero(),
            is_resolved: false,
            outcome: 0,
        }
    }
    public entry fun create(description: vector<u8>, ctx: &mut TxContext) {
        let market = new(description, ctx);
        transfer::share_object(market);
    }
    public entry fun create_portfolio(ctx: &mut TxContext) {
        let portfolio = Portfolio {
            id: object::new(ctx),
            yes_shares: balance::zero(),
            no_shares: balance::zero(),
        };
        transfer::public_transfer(portfolio, tx_context::sender(ctx));
    }
    
    // --- Fungsi Kalkulasi Harga (View) ---
    public fun get_yes_price(market: &Market, amount_of_shares: u64): u64 {
        let yes_supply = balance::supply_value(&market.yes_share_supply);
        let no_supply = balance::supply_value(&market.no_share_supply);
        if (yes_supply == 0 && no_supply == 0) { return 500_000_000 * amount_of_shares };
        let price_per_share = (yes_supply * 1_000_000_000) / (yes_supply + no_supply);
        price_per_share * amount_of_shares
    }
    public fun get_no_price(market: &Market, amount_of_shares: u64): u64 {
        let yes_price = get_yes_price(market, amount_of_shares);
        (1_000_000_000 * amount_of_shares) - yes_price
    }

    // --- Fungsi untuk menghitung payout saat selling ---
    public fun get_sell_payout(market: &Market, amount_of_shares: u64, is_yes_share: bool): u64 {
        let total_supply = balance::supply_value(&market.yes_share_supply) + balance::supply_value(&market.no_share_supply);
        if (total_supply == 0) { return 0 };
        
        let pool_value = balance::value(&market.pool);
        // Payout proporsional berdasarkan share yang dijual
        (pool_value * amount_of_shares) / total_supply
    }

    // --- FUNGSI AMM LENGKAP DENGAN PEMBAYARAN YANG BENAR ---
    public entry fun buy_yes(
        market: &mut Market, portfolio: &mut Portfolio, payment: &mut Coin<SUI>, amount_to_buy: u64, ctx: &mut TxContext
    ) {
        assert!(!market.is_resolved, EMarketResolved);
        let required_payment = get_yes_price(market, amount_to_buy);
        assert!(coin::value(payment) >= required_payment, EIncorrectPayment);

        let payment_coin = coin::split(payment, required_payment, ctx);
        let payment_balance = coin::into_balance(payment_coin);
        balance::join(&mut market.pool, payment_balance);

        let new_shares = balance::increase_supply(&mut market.yes_share_supply, amount_to_buy);
        balance::join(&mut portfolio.yes_shares, new_shares);
    }
    
    public entry fun buy_no(
        market: &mut Market, portfolio: &mut Portfolio, payment: &mut Coin<SUI>, amount_to_buy: u64, ctx: &mut TxContext
    ) {
        assert!(!market.is_resolved, EMarketResolved);
        let required_payment = get_no_price(market, amount_to_buy);
        assert!(coin::value(payment) >= required_payment, EIncorrectPayment);

        let payment_coin = coin::split(payment, required_payment, ctx);
        let payment_balance = coin::into_balance(payment_coin);
        balance::join(&mut market.pool, payment_balance);
        
        let new_shares = balance::increase_supply(&mut market.no_share_supply, amount_to_buy);
        balance::join(&mut portfolio.no_shares, new_shares);
    }
    
    public entry fun sell_yes(
        market: &mut Market, portfolio: &mut Portfolio, amount_to_sell: u64, ctx: &mut TxContext
    ) {
        assert!(!market.is_resolved, EMarketResolved);
        assert!(balance::value(&portfolio.yes_shares) >= amount_to_sell, EInsufficientShares);
        
        let payout_amount = get_sell_payout(market, amount_to_sell, true);
        assert!(balance::value(&market.pool) >= payout_amount, EInsufficientPoolFunds);
        
        let shares_to_sell = balance::split(&mut portfolio.yes_shares, amount_to_sell);
        balance::decrease_supply(&mut market.yes_share_supply, shares_to_sell);
        let payout_coin = coin::take(&mut market.pool, payout_amount, ctx);
        transfer::public_transfer(payout_coin, tx_context::sender(ctx));
    }
    
    public entry fun sell_no(
        market: &mut Market, portfolio: &mut Portfolio, amount_to_sell: u64, ctx: &mut TxContext
    ) {
        assert!(!market.is_resolved, EMarketResolved);
        assert!(balance::value(&portfolio.no_shares) >= amount_to_sell, EInsufficientShares);
        
        let payout_amount = get_sell_payout(market, amount_to_sell, false);
        assert!(balance::value(&market.pool) >= payout_amount, EInsufficientPoolFunds);
        
        let shares_to_sell = balance::split(&mut portfolio.no_shares, amount_to_sell);
        balance::decrease_supply(&mut market.no_share_supply, shares_to_sell);
        let payout_coin = coin::take(&mut market.pool, payout_amount, ctx);
        transfer::public_transfer(payout_coin, tx_context::sender(ctx));
    }

    // --- FUNGSI BARU: Penyelesaian Pasar ---
    public entry fun resolve_market(
        market: &mut Market, 
        outcome: u8
    ) {
        assert!(!market.is_resolved, EMarketResolved);
        market.is_resolved = true;
        market.outcome = outcome;
    }

    public entry fun redeem_winnings(
        market: &mut Market, portfolio: &mut Portfolio, ctx: &mut TxContext
    ) {
        assert!(market.is_resolved, EMarketNotResolved);
        let mut payout_amount = 0;
        let sender = tx_context::sender(ctx);
        if (market.outcome == 1) { // YES menang
            let total_shares = balance::value(&portfolio.yes_shares);
            if (total_shares > 0) {
                payout_amount = total_shares * 1_000_000_000;
                let shares_to_redeem = balance::split(&mut portfolio.yes_shares, total_shares);
                balance::decrease_supply(&mut market.yes_share_supply, shares_to_redeem);
            }
        } else if (market.outcome == 2) { // NO menang
            let total_shares = balance::value(&portfolio.no_shares);
            if (total_shares > 0) {
                payout_amount = total_shares * 1_000_000_000;
                let shares_to_redeem = balance::split(&mut portfolio.no_shares, total_shares);
                balance::decrease_supply(&mut market.no_share_supply, shares_to_redeem);
            }
        } else {
            abort EWrongOutcome;
        };
        if (payout_amount > 0) {
            let payout_coin = coin::take(&mut market.pool, payout_amount, ctx);
            transfer::public_transfer(payout_coin, sender);
        }
    }

    // --- View Functions ---
    public fun get_market_info(market: &Market): (String, u64, u64, u64, bool, u8) {
        (
            market.description,
            balance::supply_value(&market.yes_share_supply),
            balance::supply_value(&market.no_share_supply),
            balance::value(&market.pool),
            market.is_resolved,
            market.outcome
        )
    }

    public fun get_portfolio_info(portfolio: &Portfolio): (u64, u64) {
        (
            balance::value(&portfolio.yes_shares),
            balance::value(&portfolio.no_shares)
        )
    }
}