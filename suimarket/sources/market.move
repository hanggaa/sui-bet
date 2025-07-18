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

    // --- FUNGSI AMM LENGKAP DENGAN PEMBAYARAN YANG BENAR ---
    public entry fun buy_yes(
        market: &mut Market, portfolio: &mut Portfolio, payment: &mut Coin<SUI>, amount_to_buy: u64, ctx: &mut TxContext
    ) {
        assert!(!market.is_resolved, EMarketResolved);
        let required_payment = get_yes_price(market, amount_to_buy);
        assert!(coin::value(payment) >= required_payment, EIncorrectPayment);

        // === PERBAIKAN DI SINI ===
        // 1. Pisahkan koin pembayaran menjadi objek Coin baru
        let payment_coin = coin::split(payment, required_payment, ctx);
        // 2. Ambil Balance dari Coin baru tersebut dan hancurkan Coin-nya
        let payment_balance = coin::into_balance(payment_coin);
        // 3. Gabungkan Balance ke dalam kolam pasar
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
        let payout_amount = get_yes_price(market, amount_to_sell);
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
        let payout_amount = get_no_price(market, amount_to_sell);
        let shares_to_sell = balance::split(&mut portfolio.no_shares, amount_to_sell);
        balance::decrease_supply(&mut market.no_share_supply, shares_to_sell);
        let payout_coin = coin::take(&mut market.pool, payout_amount, ctx);
        transfer::public_transfer(payout_coin, tx_context::sender(ctx));
    }
}