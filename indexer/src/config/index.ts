import dotenv from 'dotenv';
import { ethers } from 'ethers';

dotenv.config();

export const config = {
  rpcUrlWss: process.env.RPC_URL_WSS!,
  rpcUrlHttps: process.env.RPC_URL_HTTPS!,
  rpcUrlWssFallback: process.env.RPC_URL_WSS_FALLBACK!,
  rpcUrlHttpsFallback: process.env.RPC_URL_HTTPS_FALLBACK!,
  network: process.env.NETWORK || 'localhost',
}

export const providerRealTime = new ethers.WebSocketProvider(config.rpcUrlWss);

export const providerHistory = new ethers.FallbackProvider([
  { provider: new ethers.JsonRpcProvider(config.rpcUrlHttps), priority: 1 },
  { provider: new ethers.JsonRpcProvider(config.rpcUrlHttpsFallback), priority: 2 },
])