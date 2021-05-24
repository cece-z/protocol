import { BaseContract } from '@0x/base-contract';
import { ContractVersionData , SupportedProvider } from 'ethereum-types';

import { artifacts } from '../artifacts';
import { DUMMY_PROVIDER } from '../constants';
import { Chain } from '../utils/chain';
import { Address, Bytes } from '../types';

import { ERC20BridgeSource } from './types';
import { ContractHelper, getBytecodeFromArtifact, getDeterministicContractAddressFromArtifact } from './utils';

interface SamplerContract extends BaseContract {
    new (address: Address, provider: SupportedProvider): SamplerContract;
}

export class SourceSampler<
    TSource extends keyof(ERC20BridgeSource),
    TSellSamplerContract extends SamplerContract,
    TBuySamplerContract extens SamplerContract
> {
    protected readonly _sellContract: TSellSamplerContract;
    protected readonly _buyContract: TBuySamplerContract;
    protected readonly _sellContractHelper: ContractHelper<TSellSamplerContract>;
    protected readonly _buyContract: TBuySamplerContract;
    protected readonly _buyContractHelper: ContractHelper<TBuySamplerContract>;
    protected readonly _sellContractBytecode: Bytes;
    protected readonly _buyContractBytecode: Bytes;

    protected constructor(chain: Chain) {
        const sellContractArtifact = artifacts[`${TSource}SellSampler`];
        const buyContractArtifact = artifacts[`${TSource}BuySampler`];
        this._sellContractBytecode = getBytecodeFromArtifact(sellContractArtifact)
        this._buyContractBytecode = getBytecodeFromArtifact(buyContractArtifact)
        this._sellContract = new TSellSamplerContract(
            getDeterministicContractAddressFromArtifact(sellContractArtifact),
            DUMMY_PROVIDER,
        );
        this._buyContract = new TBuySamplerContract(
            getDeterministicContractAddressFromArtifact(buyContractArtifact),
            DUMMY_PROVIDER,
        );
        this._sellContractHelper = new ContractHelper(
            chain,
            this._sellContract,
        );
        this._buyContractHelper = new ContractHelper(
            chain,
            this._buyContract,
        );
    }
}
