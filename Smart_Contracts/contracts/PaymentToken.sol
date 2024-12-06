// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";

/**
* @title PaymentToken
* @dev ERC20 token for payments and bonuses in manufacturing system
*/
contract PaymentToken is ERC20, ERC20Burnable, Pausable, AccessControl {
    bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");
    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");

    // Events
    event MinterAdded(address indexed account);
    event MinterRemoved(address indexed account);
    event EmergencyTransfer(address indexed from, address indexed to, uint256 amount);

    // Errors
    error InvalidParameters();
    error InsufficientBalance();
    error NotAuthorized();

    /**
     * @dev Constructor configuring the name andsymbol
   */
    constructor() ERC20("Manufacturing Payment Token", "MPT") {
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(PAUSER_ROLE, msg.sender);
        _grantRole(MINTER_ROLE, msg.sender);
    }

    /**
     * @dev Pauses all token transfers
   * Can only be called by an account with the PAUSER_ROLE role.
   */
    function pause() public onlyRole(PAUSER_ROLE) {
        _pause();
    }

    /**
     * @dev Unpauses all token transfers
   * Can only be called by an account with the PAUSER_ROLE role.
   */
    function unpause() public onlyRole(PAUSER_ROLE) {
        _unpause();
    }

    /**
     * @dev Create new tokens
   * @param to address that will receive the tokens
   * @param amount amount of tokens to create
   */
    function mint(address to, uint256 amount) public onlyRole(MINTER_ROLE) {
        if(to == address(0) || amount == 0) revert InvalidParameters();
        _mint(to, amount);
    }

    /**
     * @dev Add a new address as minter
   * @param account address to be added as minter
   */
    function addMinter(address account) public onlyRole(DEFAULT_ADMIN_ROLE) {
        if(account == address(0)) revert InvalidParameters();
        grantRole(MINTER_ROLE, account);
        emit MinterAdded(account);
    }

    /**
     * @dev Remove an address as minter
   * @param account address to be removed as minter
   */
    function removeMinter(address account) public onlyRole(DEFAULT_ADMIN_ROLE) {
        if(account == address(0)) revert InvalidParameters();
        revokeRole(MINTER_ROLE, account);
        emit MinterRemoved(account);
    }

    /**
     * @dev Transfer tokens in case of emergency
   * @param from address to transfer from
   * @param to address to receive tokens from
   * @param amount amount of tokens to transfer
   */
    function emergencyTransfer(
        address from,
        address to,
        uint256 amount
    ) public onlyRole(DEFAULT_ADMIN_ROLE) {
        if(to == address(0) || amount == 0) revert InvalidParameters();
        if(balanceOf(from) < amount) revert InsufficientBalance();

        _transfer(from, to, amount);
        emit EmergencyTransfer(from, to, amount);
    }

    /**
     * @dev Burns tokens from a specific address
   * @param from address to burn tokens from
   * @param amount amount of tokens to burn
   */
    function burnFrom(address from, uint256 amount)
    public
    override
    onlyRole(MINTER_ROLE)
    {
        if(from == address(0) || amount == 0) revert InvalidParameters();
        if(balanceOf(from) < amount) revert InsufficientBalance();

        _burn(from, amount);
    }

    /**
     * @dev Hook to be executed prior to any token transfer
   */
    function _beforeTokenTransfer(
        address,
        address,
        uint256
    ) internal virtual {
        require(!paused(), "ERC20Pausable: token transfer while paused");
    }

    /**
     * @dev Supports AccessControl and ERC20 interfaces
   */
    function supportsInterface(bytes4 interfaceId)
    public
    view
    override(AccessControl)
    returns (bool)
    {
        return super.supportsInterface(interfaceId);
    }

    /**
     * @dev Function to receive ETH (required to receive ETH)
   */
    receive() external payable {
        revert("Direct ETH payments not accepted");
    }
}