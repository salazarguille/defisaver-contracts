pragma solidity ^0.6.0;

import "../../flashloan/aave/FlashLoanReceiverBase.sol";
import "../../interfaces/DSProxyInterface.sol";
import "../../interfaces/ERC20.sol";

/// @title Contract that receives the FL from Aave for Repays/Boost
contract CompoundSaverFlashLoan is FlashLoanReceiverBase {
    ILendingPoolAddressesProvider public LENDING_POOL_ADDRESS_PROVIDER = ILendingPoolAddressesProvider(0x24a42fD28C976A61Df5D00D0599C34c4f90748c8);

    address payable public COMPOUND_SAVER_FLASH_PROXY;
    address public constant ETH_ADDRESS = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;

    address public owner;

    constructor()
        FlashLoanReceiverBase(LENDING_POOL_ADDRESS_PROVIDER)
        public {
            owner = msg.sender;
    }

    /// @notice Called by Aave when sending back the FL amount
    /// @param _reserve The address of the borrowed token
    /// @param _amount Amount of FL tokens received
    /// @param _fee FL Aave fee
    /// @param _params The params that are sent from the original FL caller contract
   function executeOperation(
        address _reserve,
        uint256 _amount,
        uint256 _fee,
        bytes calldata _params)
    external override {
        // Format the call data for DSProxy
        (bytes memory proxyData, address payable proxyAddr) = packFunctionCall(_amount, _fee, _params);

        // Send Flash loan amount to DSProxy
        sendLoanToProxy(proxyAddr, _reserve, _amount);

        // Execute the DSProxy call
        DSProxyInterface(proxyAddr).execute(COMPOUND_SAVER_FLASH_PROXY, proxyData);

        // Repay the loan with the money DSProxy sent back
        transferFundsBackToPoolInternal(_reserve, _amount.add(_fee));

        // if there is some eth left (0x fee), return it to user
        if (address(this).balance > 0) {
            tx.origin.transfer(address(this).balance);
        }
    }

    /// @notice Formats function data call so we can call it through DSProxy
    /// @param _amount Amount of FL
    /// @param _fee Fee of the FL
    /// @param _params Saver proxy params
    /// @return proxyData Formated function call data
    function packFunctionCall(uint _amount, uint _fee, bytes memory _params) internal returns (bytes memory proxyData, address payable) {
        (
            uint[5] memory data, // amount, minPrice, exchangeType, gasCost, 0xPrice
            address[3] memory addrData, // cCollAddress, cBorrowAddress, exchangeAddress
            bytes memory callData,
            bool isRepay,
            address payable proxyAddr
        )
        = abi.decode(_params, (uint256[5],address[3],bytes,bool,address));

        uint[2] memory flashLoanData = [_amount, _fee];

        if (isRepay) {
            proxyData = abi.encodeWithSignature("flashRepay(uint256[5],address[3],bytes,uint256[2])", data, addrData, callData, flashLoanData);
        } else {
            proxyData = abi.encodeWithSignature("flashBoost(uint256[5],address[3],bytes,uint256[2])", data, addrData, callData, flashLoanData);
        }

        return (proxyData, proxyAddr);
    }

    /// @notice Send the FL funds received to DSProxy
    /// @param _proxy DSProxy address
    /// @param _reserve Token address
    /// @param _amount Amount of tokens
    function sendLoanToProxy(address payable _proxy, address _reserve, uint _amount) internal {
        if (_reserve != ETH_ADDRESS) {
            ERC20(_reserve).transfer(_proxy, _amount);
        }

        _proxy.transfer(address(this).balance);
    }

    /// @notice Sets the Saver flash proxy address
    /// @dev Only callable once by the owner
    /// @param _saverFlashProxy The flash proxy address
    function setSaverFlashProxy(address payable _saverFlashProxy) public {
        require(msg.sender == owner);

        COMPOUND_SAVER_FLASH_PROXY = _saverFlashProxy;
    }

    receive() external override payable {}
}
