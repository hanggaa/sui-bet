module suimarket::factory {
    use sui::tx_context::{Self, TxContext};
    use sui::transfer;
    use sui::object::{Self, UID};
    
    // Impor modul market secara keseluruhan
    use suimarket::market;

    public struct FactoryAdminCap has key, store {
        id: UID
    }

    fun init(ctx: &mut TxContext) {
        transfer::transfer(FactoryAdminCap { id: object::new(ctx) }, tx_context::sender(ctx));
    }

    // Factory sekarang hanya memanggil fungsi 'create' dari market
    public entry fun create_market(
        _admin_cap: &FactoryAdminCap,
        description: vector<u8>,
        ctx: &mut TxContext
    ) {
        // Mendelegasikan seluruh proses pembuatan ke modul 'market'
        market::create(description, ctx);
    }
}