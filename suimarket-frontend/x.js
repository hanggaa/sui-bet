import React, { useEffect, useState, useCallback } from 'react';
import { createRoot } from 'react-dom/client';
import { SuiClientProvider, WalletProvider, ConnectButton, useCurrentAccount, useSuiClient, useSignAndExecuteTransaction } from '@mysten/dapp-kit';
import { SuiClient, getFullnodeUrl } from '@mysten/sui/client';
import { Transaction } from '@mysten/sui/transactions';
import { QueryClient, QueryClientProvider } from '@tanstack/react-query';
import '@mysten/dapp-kit/dist/index.css';
import './style.css';

// === GANTI DENGAN PACKAGE ID ANDA! ===
const PACKAGE_ID = "0xb991eef22dbc92665bfb90143cc822389e9d66ca70a6771ceb06449f8c1408f9";
// Kita akan menambahkan ID AdminCap & Market nanti
// const FACTORY_ADMIN_CAP_ID = "0x...";

const queryClient = new QueryClient();
const networks = { testnet: { url: getFullnodeUrl('testnet') } };

function App() {
  const account = useCurrentAccount();
  const suiClient = useSuiClient();
  const { mutate: signAndExecute } = useSignAndExecuteTransaction();
  const [markets, setMarkets] = useState([]);
  const [portfolio, setPortfolio] = useState(null);
  const [loading, setLoading] = useState(true);

  const fetchMarkets = useCallback(async () => {
    // ... (kode tidak berubah)
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
          console.log("Portfolio created! Digest:", result.digest);
          alert("Your portfolio has been created!");
          setTimeout(() => { if (account) fetchPortfolio(account.address); }, 2000);
        },
        onError: (error) => alert("Failed to create portfolio: " + error.message),
      }
    );
  }, [account, signAndExecute, fetchPortfolio]);

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
      <div>
        <header><h1>SuiMarket</h1><ConnectButton /></header>
        <div>Loading...</div>
      </div>
    );
  }

  return (
    <div>
      <header>
        <h1>SuiMarket</h1>
        <ConnectButton />
      </header>
      
      <div className="market-list">
        <h2>Active Markets</h2>
        {markets.length === 0 ? (
          <p>No active markets found.</p>
        ) : (
          markets.map(market => (
            <div key={market.data.objectId} className="market-card">
              <h3>{market.data.content.fields.description}</h3>
            </div>
          ))
        )}
      </div>

      {account && (
        <div className="portfolio-section">
          <h2>My Portfolio</h2>
          {!portfolio ? (
            <p>You haven't created a portfolio yet. <button onClick={handleCreatePortfolio}>Create Portfolio</button></p>
          ) : (
            <div className="market-card">
                {/* === PERBAIKAN DI SINI === */}
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
            <WalletProvider>
                <App />
            </WalletProvider>
        </SuiClientProvider>
    </QueryClientProvider>
  </React.StrictMode>
);