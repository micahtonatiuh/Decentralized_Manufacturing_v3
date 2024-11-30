// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";

contract IPFSRegistry is Ownable, ReentrancyGuard, Pausable {
    // Token para pagos y bonificaciones
    IERC20 public paymentToken;

    // Porcentaje que va al pool de bonificaciones (10%)
    uint256 public constant BONIFICATION_POOL_PERCENTAGE = 10;

    // Estructuras
    struct Design {
        bool isRegistered;
        address owner;
        uint256 price;
        uint256 bonificationPool;
        uint256 totalLicenses;
        bool active;
    }

    // Mappings principales
    mapping(string => Design) public designs;
    mapping(string => mapping(address => bool)) public designLicenses;

    // Mapping para el control de acceso a bonificaciones
    mapping(address => bool) public bonificationManagers;

    // Events
    event DesignRegistered(string indexed designHash, address indexed owner, uint256 price, uint256 initialPool);
    event DesignLicensed(string indexed designHash, address indexed licensee, uint256 price);
    event BonificationProcessed(string indexed designHash, address indexed recipient, uint256 amount);
    event BonificationPoolIncreased(string indexed designHash, uint256 amount);
    event DesignStatusUpdated(string indexed designHash, bool active);
    event BonificationManagerUpdated(address indexed manager, bool status);

    // Errors
    error InvalidAddress();
    error InvalidAmount();
    error DesignNotRegistered();
    error InsufficientPool();
    error AlreadyLicensed();
    error NotAuthorized();
    error DesignNotActive();

    constructor(address _paymentToken) Ownable(msg.sender) {
        if(_paymentToken == address(0)) revert InvalidAddress();
        paymentToken = IERC20(_paymentToken);
    }

    modifier onlyBonificationManager() {
        if(!bonificationManagers[msg.sender] && msg.sender != owner())
            revert NotAuthorized();
        _;
    }

    function setBonificationManager(address manager, bool status) external onlyOwner {
        if(manager == address(0)) revert InvalidAddress();
        bonificationManagers[manager] = status;
        emit BonificationManagerUpdated(manager, status);
    }

    function registerDesign(
        string memory designHash,
        uint256 price,
        uint256 initialBonificationPool
    ) external whenNotPaused nonReentrant {
        if(price == 0) revert InvalidAmount();
        if(designs[designHash].isRegistered) revert AlreadyLicensed();

        // Transferir tokens para el pool inicial de bonificaciones
        if(initialBonificationPool > 0) {
            require(
                paymentToken.transferFrom(msg.sender, address(this), initialBonificationPool),
                "Failed to transfer initial pool"
            );
        }

        designs[designHash] = Design({
            isRegistered: true,
            owner: msg.sender,
            price: price,
            bonificationPool: initialBonificationPool,
            totalLicenses: 0,
            active: true
        });

        // El dueño obtiene automáticamente una licencia
        designLicenses[designHash][msg.sender] = true;

        emit DesignRegistered(designHash, msg.sender, price, initialBonificationPool);
    }

    function licenseDesign(string memory designHash) external nonReentrant whenNotPaused {
        Design storage design = designs[designHash];
        if(!design.isRegistered) revert DesignNotRegistered();
        if(!design.active) revert DesignNotActive();
        if(designLicenses[designHash][msg.sender]) revert AlreadyLicensed();

        uint256 price = design.price;
        uint256 bonificationAmount = (price * BONIFICATION_POOL_PERCENTAGE) / 100;
        uint256 ownerAmount = price - bonificationAmount;

        // Transferir el pago al dueño
        require(
            paymentToken.transferFrom(msg.sender, design.owner, ownerAmount),
            "Failed to transfer payment to owner"
        );

        // Transferir al pool de bonificaciones
        require(
            paymentToken.transferFrom(msg.sender, address(this), bonificationAmount),
            "Failed to transfer to bonification pool"
        );

        // Actualizar estado
        design.bonificationPool += bonificationAmount;
        design.totalLicenses++;
        designLicenses[designHash][msg.sender] = true;

        emit DesignLicensed(designHash, msg.sender, price);
        emit BonificationPoolIncreased(designHash, bonificationAmount);
    }

    function processBonification(
        string memory designHash,
        address recipient,
        uint256 amount
    ) external nonReentrant whenNotPaused onlyBonificationManager {
        Design storage design = designs[designHash];
        if(!design.isRegistered) revert DesignNotRegistered();
        if(recipient == address(0)) revert InvalidAddress();
        if(amount == 0) revert InvalidAmount();
        if(design.bonificationPool < amount) revert InsufficientPool();

        design.bonificationPool -= amount;

        require(
            paymentToken.transfer(recipient, amount),
            "Failed to transfer bonification"
        );

        emit BonificationProcessed(designHash, recipient, amount);
    }

    function updateDesignStatus(string memory designHash, bool active)
    external
    onlyOwner
    {
        if(!designs[designHash].isRegistered) revert DesignNotRegistered();
        designs[designHash].active = active;
        emit DesignStatusUpdated(designHash, active);
    }

    // View functions
    function isDesignLicensed(string memory designHash, address user)
    external
    view
    returns (bool)
    {
        return designLicenses[designHash][user];
    }

    function getDesignDetails(string memory designHash)
    external
    view
    returns (
        bool isRegistered,
        address owner,
        uint256 price,
        uint256 bonificationPool,
        uint256 totalLicenses,
        bool active
    )
    {
        Design storage design = designs[designHash];
        return (
            design.isRegistered,
            design.owner,
            design.price,
            design.bonificationPool,
            design.totalLicenses,
            design.active
        );
    }

    // Emergency functions
    function pause() external onlyOwner {
        _pause();
    }

    function unpause() external onlyOwner {
        _unpause();
    }

    function emergencyWithdraw(
        address token,
        address to,
        uint256 amount
    ) external onlyOwner {
        if(to == address(0)) revert InvalidAddress();
        if(amount == 0) revert InvalidAmount();

        IERC20(token).transfer(to, amount);
    }
}