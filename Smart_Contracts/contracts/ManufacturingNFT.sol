// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/ERC721URIStorage.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract ManufacturingNFT is ERC721URIStorage, Ownable {
    // Reemplazamos el Counter por un uint256
    uint256 private _currentTokenId;

    struct Certificate {
        uint256 manufacturingId;
        string designHash;
        uint256 completionTime;
        uint256 qualityScore;
        bool verified;
        string metadata;
    }

    // State variables
    mapping(uint256 => Certificate) public certificates;
    mapping(uint256 => bool) public manufacturingCertified;
    mapping(address => bool) public authorizedMinters;

    // Events
    event CertificateMinted(uint256 indexed tokenId, uint256 indexed manufacturingId);
    event CertificateVerified(uint256 indexed tokenId);
    event MinterAuthorized(address indexed minter);
    event MinterRemoved(address indexed minter);

    constructor()
    ERC721("Manufacturing Certificate", "MFGC")
    Ownable(msg.sender)
    {
        _currentTokenId = 0;
    }

    function isExist(uint256 tokenId) internal view returns (bool) {
        return certificates[tokenId].manufacturingId != 0;
    }

    modifier onlyAuthorizedMinter() {
        require(authorizedMinters[msg.sender], "Not authorized to mint");
        _;
    }

    function authorizeMinter(address minter) external onlyOwner {
        require(!authorizedMinters[minter], "Already authorized");
        authorizedMinters[minter] = true;
        emit MinterAuthorized(minter);
    }

    function removeMinter(address minter) external onlyOwner {
        require(authorizedMinters[minter], "Not authorized");
        authorizedMinters[minter] = false;
        emit MinterRemoved(minter);
    }

    function mintCertificate(
        address to,
        uint256 manufacturingId,
        string memory designHash,
        uint256 completionTime,
        uint256 qualityScore,
        string memory tokenURI_,
        string memory metadata
    )
    external
    onlyAuthorizedMinter
    returns (uint256)
    {
        require(!manufacturingCertified[manufacturingId], "Already certified");
        require(bytes(designHash).length > 0, "Invalid design hash");
        require(completionTime > 0, "Invalid completion time");
        require(qualityScore > 0 && qualityScore <= 100, "Invalid quality score");

        // Incrementamos el contador de manera segura
        unchecked {
            _currentTokenId++;
        }
        uint256 newTokenId = _currentTokenId;

        _mint(to, newTokenId);
        _setTokenURI(newTokenId, tokenURI_);

        certificates[newTokenId] = Certificate({
            manufacturingId: manufacturingId,
            designHash: designHash,
            completionTime: completionTime,
            qualityScore: qualityScore,
            verified: false,
            metadata: metadata
        });

        manufacturingCertified[manufacturingId] = true;
        emit CertificateMinted(newTokenId, manufacturingId);

        return newTokenId;
    }

    function verifyCertificate(uint256 tokenId) external onlyOwner {
        require(isExist(tokenId), "Certificate does not exist");
        require(!certificates[tokenId].verified, "Already verified");

        certificates[tokenId].verified = true;
        emit CertificateVerified(tokenId);
    }

    function getCertificate(uint256 tokenId)
    external
    view
    returns (
        uint256 manufacturingId,
        string memory designHash,
        uint256 completionTime,
        uint256 qualityScore,
        bool verified,
        string memory metadata
    )
    {
        require(isExist(tokenId), "Certificate does not exist");
        Certificate memory cert = certificates[tokenId];
        return (
            cert.manufacturingId,
            cert.designHash,
            cert.completionTime,
            cert.qualityScore,
            cert.verified,
            cert.metadata
        );
    }

    function isCertified(uint256 manufacturingId) external view returns (bool) {
        return manufacturingCertified[manufacturingId];
    }

    function supportsInterface(bytes4 interfaceId)
    public
    view
    override(ERC721URIStorage)
    returns (bool)
    {
        return super.supportsInterface(interfaceId);
    }
}