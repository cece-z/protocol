import { ChainId } from '@0x/contract-addresses';
import { BigNumber } from '@0x/utils';

import { SourceSampler} from "../source_sampler";
import { Address } from '../types';
import { Chain } from '../utils/chain';
import { valueByChainId } from '../utils/utils';
import { UniswapV3BuySamplerContract, UniswapV3SellSamplerContract } from '../wrappers';


import { DexSample, ERC20BridgeSource, FillData } from "./types";

interface SamplerConfig = {
    quoter: Address,
    router: Address,
};

export const UNISWAP_V3_CONFIG_BY_CHAIN_ID = valueByChainId(
    {
        [ChainId.Mainnet]: {
            quoter: '0xb27308f9f90d607463bb33ea1bebb41c27ce5ab6',
            router: '0xe592427a0aece92de3edee1f18e0157c05861564',
        },
        [ChainId.Ropsten]: {
            quoter: '0x2f9e608fd881861b8916257b76613cb22ee0652c',
            router: '0x03782388516e94fcd4c18666303601a12aa729ea',
        },
    },
    { quoter: NULL_ADDRESS, router: NULL_ADDRESS },
);

export interface UniswapV3FillData extends FillData {
    tokenAddressPath: string[];
    router: string;
    pathAmounts: Array<{ uniswapPath: string; inputAmount: BigNumber }>;
}

export function UNISWAP_V3_GAS_SCHEDULE(fillData: FillData): number {
      let gas = 160e3;
      const path = (fillData as UniswapV3FillData).tokenAddressPath;
      if (path.length > 2) {
          gas += (path.length - 2) * 117e3; // +117k for each hop.
      }
      return gas;
}

export class UniswapV3Sampler extends
    SourceSampler<'UniswapV3', UniswapV3SellSamplerContract, UniswapV3BuySamplerContract>
{
    private readonly _config: SamplerConfig;
    private readonly _chain: Chain;

    async createAsync(chain: Chain): Promise<UniswapV3Sampler> {
        return new UniswapV3Sampler(chain);
    }

    protected constructor(chain: ChainId) {
        super(chain);
        this._chain = chain;
        this._config = UNISWAP_V3_CONFIG_BY_CHAIN_ID[chain.chainId];
    }

    public getSellQuotesAsync(
        tokenAddressPath: string[],
        takerFillAmounts: BigNumber[],
    ): Promise<DexSample<UniswapV3FillData>[]> {
        const [uniswapPaths, samples] = await this._sellContractHelper.ethCallAsync(
            this._sellContract.sampleSells,
            [
                this._config.quoter,
                tokenAddressPath,
                takerFillAmounts,
            ],
        );
        return takerFillAmounts.map((a, i) => {
            return {
                source: ERC20BridgeSource.UniswapV3,
                fillData: {
                    router: this._config.router,
                    tokenAddressPath: tokenAddressPath,
                    uniswapPath: uniswapPaths[i],
                },
                input: a,
                output: samples[i],
            };
        });
    }

    public getBuyQuotesAsync(
        tokenAddressPath: string[],
        makerFillAmounts: BigNumber[],
    ): Promise<DexSample<UniswapV3FillData>[]> {
        const [uniswapPaths, samples] = await this._buyContractHelper.ethCallAsync(
            this._buyContract.sampleSells,
            [
                this._config.quoter,
                tokenAddressPath,
                makerFillAmounts,
            ],
        );
        return makerFillAmounts.map((a, i) => {
            return {
                source: ERC20BridgeSource.UniswapV3,
                fillData: {
                    router: this._config.router,
                    tokenAddressPath: tokenAddressPath,
                    uniswapPath: uniswapPaths[i],
                },
                input: a,
                output: samples[i],
            };
        });
    }
  }
