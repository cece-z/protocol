// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.6;

import "@0x/contracts-erc20/contracts/src/v06/LibERC20TokenV06.sol";

contract HackedERC20 {

    using LibERC20TokenV06 for IERC20TokenV06;

    struct ShadowedAmount {
        bool isShadowed;
        uint256 lastTrueAmount;
        uint256 shadowedAmount;
    }

    struct Storage {
        mapping(address=>ShadowedAmount) shadowedBalances;
        mapping(address=>mapping(address=>ShadowedAmount)) shadowedAllowances;
    }

    bytes32 private constant STORAGE_SLOT = 0x64fd48372774b9637ace5c8c7a951f04ea13c793935207f2eada5382a0ec82cb;

    receive() external payable {}

    fallback() payable external {
        bytes memory r = _forwardCallToImpl();
        assembly { return(add(r, 32), mload(r)) }
    }

    function balanceOf(address owner)
        external
        /* view */
        returns (uint256 balance)
    {
        ShadowedAmount memory sBal = _getSyncedBalance(owner);
        return sBal.shadowedAmount;
    }

    function allowance(address owner, address spender)
        external
        /* view */
        returns (uint256 allowance_)
    {
        ShadowedAmount memory sBal = _getSyncedAllowance(owner, spender);
        return sBal.shadowedAmount;
    }

    function transferFrom(address from, address to, uint256 amount)
        public
        returns (bool)
    {
        ShadowedAmount memory sFromBal = _getSyncedBalance(from);
        ShadowedAmount memory sToBal = _getSyncedBalance(to);
        ShadowedAmount memory sAllowance = _getSyncedAllowance(from, msg.sender);
        if (from != msg.sender && sAllowance.shadowedAmount != uint256(-1)) {
            sAllowance.shadowedAmount = _sub(
                sAllowance.shadowedAmount,
                amount,
                'HackedERC20/ALLOWANCE_UNDERFLOW'
            );
        }
        sFromBal.shadowedAmount = _sub(
            sFromBal.shadowedAmount,
            amount,
            'HackedERC20/BALANCE_UNDERFLOW'
        );
        sToBal.shadowedAmount += _add(
            sToBal.shadowedAmount,
            amount,
            'HackedERC20/BALANCE_OVERFLOW'
        );
        _writeSyncedBalance(from, sFromBal);
        _writeSyncedBalance(to, sToBal);
        _writeSyncedAllowance(from, msg.sender, sAllowance);
        return true;
    }

    function transfer(address to, uint256 amount)
        external
        returns (bool)
    {
        transferFrom(msg.sender, to, amount);
        return true;
    }

    function approve(address spender, uint256 amount)
        external
        returns (bool)
    {
        ShadowedAmount memory sAllowance = _getSyncedAllowance(msg.sender, spender);
        sAllowance.shadowedAmount = amount;
        _writeSyncedAllowance(msg.sender, spender, sAllowance);
        return true;
    }

    function mint(address owner, uint256 amount)
        public
    {
        ShadowedAmount memory sBal = _getSyncedBalance(owner);
        sBal.shadowedAmount = _add(
            sBal.shadowedAmount,
            amount,
            'HackedERC20/MINT_OVERFLOW'
        );
        _writeSyncedBalance(owner, sBal);
    }

    function burn(address owner, uint256 amount)
        public
    {
        ShadowedAmount memory sBal = _getSyncedBalance(owner);
        sBal.shadowedAmount = _sub(
            sBal.shadowedAmount,
            amount,
            'HackedERC20/BURN_UNDERFLOW'
        );
        _writeSyncedBalance(owner, sBal);
    }

    function _getSyncedAllowance(address owner, address spender)
        private
        /* view */
        returns (ShadowedAmount memory sAllowance)
    {
        sAllowance = _getStorage().shadowedAllowances[owner][spender];
        uint256 trueAmount = abi.decode(
            _forwardCallToImpl(abi.encodeWithSelector(
                IERC20TokenV06.allowance.selector,
                owner,
                spender
            )),
            (uint256)
        );
        _syncShadowedAmount(sAllowance, trueAmount);
    }

    function _getSyncedBalance(address owner)
        private
        returns (ShadowedAmount memory sBal)
    {
        sBal = _getStorage().shadowedBalances[owner];
        uint256 trueAmount = abi.decode(
            _forwardCallToImpl(abi.encodeWithSelector(
                IERC20TokenV06.balanceOf.selector,
                owner
            )),
            (uint256)
        );
        _syncShadowedAmount(sBal, trueAmount);
    }

    function _syncShadowedAmount(ShadowedAmount memory sAmount, uint256 trueAmount)
        private
        pure
    {
        if (!sAmount.isShadowed) {
            sAmount.isShadowed = true;
            sAmount.shadowedAmount = trueAmount;
        } else {
            // Detect balance changes that can occur from outside of ERC20
            // functions.
            if (sAmount.lastTrueAmount > trueAmount) {
                sAmount.shadowedAmount = _sub(
                    sAmount.lastTrueAmount,
                    sAmount.lastTrueAmount - trueAmount,
                    'HackedERC20/SHADOW_ADJUSTMENT_UNDERFLOW'
                );
            } else if (sAmount.lastTrueAmount < trueAmount) {
                sAmount.shadowedAmount = _add(
                    sAmount.lastTrueAmount,
                    trueAmount - sAmount.lastTrueAmount,
                    'HackedERC20/SHADOW_ADJUSTMENT_OVERFLOW'
                );
            }
        }
        sAmount.lastTrueAmount = trueAmount;
    }

    function _writeSyncedBalance(address owner, ShadowedAmount memory sBal)
        private
    {
        _getStorage().shadowedBalances[owner] = sBal;
    }

    function _writeSyncedAllowance(
        address owner,
        address spender,
        ShadowedAmount memory sAllowance
    )
        private
    {
        _getStorage().shadowedAllowances[owner][spender] = sAllowance;
    }

    function _getStorage() private pure returns (Storage storage st) {
        bytes32 slot = STORAGE_SLOT;
        assembly { st_slot := slot }
    }

    function _getOriginalImplementationAddress()
        private
        view
        returns (address impl)
    {
        return address(uint160(address(this)) + 1);
    }

    function _forwardCallToImpl()
        private
        returns (bytes memory resultData)
    {
        bool success;
        (success, resultData) =
            _getOriginalImplementationAddress().delegatecall(msg.data);
        if (!success) {
            assembly { revert(add(resultData, 32), mload(resultData)) }
        }
    }

    function _forwardCallToImpl(bytes memory callData)
        private
        returns (bytes memory resultData)
    {
        bool success;
        (success, resultData) =
            _getOriginalImplementationAddress().delegatecall(callData);
        if (!success) {
            assembly { revert(add(resultData, 32), mload(resultData)) }
        }
    }

    function _add(uint256 a, uint256 b, string memory errMsg)
        private
        pure
        returns (uint256 c)
    {
        c = a + b;
        require(c >= a, errMsg);
    }

    function _sub(uint256 a, uint256 b, string memory errMsg)
        private
        pure
        returns (uint256 c)
    {
        c = a - b;
        require(c <= a, errMsg);
    }
}
