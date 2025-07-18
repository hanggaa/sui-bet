import React, { useEffect, useState, useCallback } from 'react';
import { createRoot } from 'react-dom/client';
import { SuiClientProvider, WalletProvider, ConnectButton, useCurrentAccount, useSuiClient, useSignAndExecuteTransaction } from '@mysten/dapp-kit';
import { SuiClient, getFullnodeUrl } from '@mysten/sui/client';
import { Transaction } from '@mysten/sui/transactions';
import { QueryClient, QueryClientProvider } from '@tanstack/react-query';
import '@mysten/dapp-kit/dist/index.css';
import './style.css';

const PACKAGE_ID = "0xb991eef22dbc92665bfb90143cc822389e9d66ca70a6771ceb06449f8c1408f9";
const MARKET_ID_HARDCODED = "0x14d09f182dae91d763d38c4f16d405ac60958e0a5450aa60f4d4496580654199";

const queryClient = new QueryClient();
const networks = { testnet: { url: getFullnodeUrl('testnet') } };

function MarketCard({ market, portfolio, onBuy }) {
    const [amount, setAmount] = useState(1);
    const account = useCurrentAccount();
    const handleBuyClick = (shareType) => {
        if (!account) return alert("Please connect your wallet first.");
        if (!portfolio) return alert("You need a portfolio to trade. Please create one below.");
        onBuy(market.data.objectId, shareType, amount);
    };
    return (
        <div className="market-card">
            <h3>{market.data.content.fields.description}</h3>
            <div className="trade-interface">
                <input type="number" value={amount} onChange={(e) => setAmount(parseInt(e.target.value, 10) || 1)} min="1"/>
                <button onClick={() => handleBuyClick('YES')}>Buy YES</button>
                <button onClick={() => handleBuyClick('NO')}>Buy NO</button>
            </div>
        </div>
    );
}

function App() {
  const account = useCurrentAccount();
  const suiClient = useSuiClient();
  const { mutate: signAndExecute } = useSignAndExecuteTransaction();
  const [markets, setMarkets] = useState([]);
  const [portfolio, setPortfolio] = useState(null);
  const [loading, setLoading] = useState(true);

  const fetchMarkets = useCallback(async () => {
    if (MARKET_ID_HARDCODED.length === 0) return setMarkets([]);
    const marketObjects = await suiClient.multiGetObjects({
        ids: [MARKET_ID_HARDCODED],
        options: { showContent: true },
    });
    setMarkets(marketObjects.filter(m => m.data));
  }, [suiClient]);

  const fetchPortfolio = useCallback(async (address) => {
    if (!address) return;
    const { data } = await suiClient.getOwnedObjects({ owner: address, options: { showContent: true }});
    const portfolioObject = data.find(obj => obj.data?.content?.type === `${PACKAGE_ID}::market::Portfolio`);
    setPortfolio(portfolioObject || null);
  }, [suiClient]);

  const handleCreatePortfolio = useCallback(() => {
    if (!account) return alert("Please connect your wallet first.");
    const tx = new Transaction();
    tx.moveCall({
      target: `${PACKAGE_ID}::market::create_portfolio`,
      arguments: [],
    });
    signAndExecute({ transaction: tx }, {
        onSuccess: (result) => {
          alert("Your portfolio has been created!");
          setTimeout(() => { if (account) fetchPortfolio(account.address); }, 2000);
        },
        onError: (error) => alert("Failed to create portfolio: " + error.message),
      }
    );
  }, [account, signAndExecute, fetchPortfolio]);

  const handleBuy = useCallback(async (marketId, shareType, amount) => {
    if (!account || !portfolio) return;
    try {
        const tx = new Transaction();
        const targetFunction = shareType === 'YES' ? 'buy_yes' : 'buy_no';
        
        // Untuk MVP, kita hardcode harga awal 0.5 SUI per saham
        // Nanti, kita akan memanggil `get_yes_price` untuk harga dinamis
        const requiredPaymentMIST = BigInt(500_000_000 * amount);
        
        // Ini adalah cara yang benar: pisahkan jumlah yang tepat dari koin gas
        const [paymentCoin] = tx.splitCoins(tx.gas, [tx.pure.u64(requiredPaymentMIST)]);

        tx.moveCall({
            target: `${PACKAGE_ID}::market::${targetFunction}`,
            arguments: [
                tx.object(marketId),
                tx.object(portfolio.data.objectId),
                paymentCoin,
                tx.pure.u64(amount)
            ],
        });

        signAndExecute({ transaction: tx }, {
            onSuccess: (result) => {
                alert(`Successfully purchased ${amount} ${shareType} shares!`);
                setTimeout(() => { if (account) fetchPortfolio(account.address); }, 2000);
            },
            onError: (error) => alert(`Purchase failed: ${error.message}`),
        });
    } catch (e) {
        alert(`An error occurred: ${e.message}`);
    }
  }, [account, portfolio, signAndExecute, fetchPortfolio]);

  useEffect(() => {
    const loadData = async () => {
      setLoading(true);
      await fetchMarkets();
      if (account) {
        await fetchPortfolio(account.address);
      }
      setLoading(false);
    };
    loadData();
  }, [account, fetchMarkets, fetchPortfolio]);

  if (loading) {
    return (
      <div><header><h1>SuiMarket</h1><ConnectButton /></header><div>Loading...</div></div>
    );
  }

  return (
    <div>
      <header><h1>SuiMarket</h1><ConnectButton /></header>
      <div className="market-list">
        <h2>Active Markets</h2>
        {markets.map(market => (
            <MarketCard key={market.data.objectId} market={market} portfolio={portfolio} onBuy={handleBuy}/>
        ))}
      </div>
      {account && (
        <div className="portfolio-section">
          <h2>My Portfolio</h2>
          {!portfolio ? (
            <p>You haven't created a portfolio yet. <button onClick={handleCreatePortfolio}>Create Portfolio</button></p>
          ) : (
            <div className="market-card">
                <p>YES Shares: {portfolio.data.content.fields.yes_shares.value}</p>
                <p>NO Shares: {portfolio.data.content.fields.no_shares.value}</p>
            </div>
          )}
        </div>
      )}
    </div>
  );
}

const root = createRoot(document.getElementById('root'));
root.render(
  <React.StrictMode>
    <QueryClientProvider client={queryClient}>
        <SuiClientProvider networks={networks} defaultNetwork="testnet">
            <WalletProvider><App /></WalletProvider>
        </SuiClientProvider>
    </QueryClientProvider>
  </React.StrictMode>
);