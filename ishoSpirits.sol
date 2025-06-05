//                              .~~:^^.                                            
//                             .B@@&@@B?.                                          
//                        :?5PP5B@@@@@@@5                                          
//                       7&@@@@@@@@@@@@&7                                          
//                      Y@@@@@@@@@@@@@@!                                           
//                      Y&@@@@@@@@@@@@@5                                           
//                       .?@@@@@@@@555?.                                           
//                         Y&@@@@@@Y                                               
//           :^7!J?J?7^:    :?J:?@@@B55?                                           
//        :JP##&#&B@@@@&G?     ^P@@@@@@5                                           
//      :?###B#B#BB&&@@@#?   ^G@@@@@@@@?                                           
//     ~B#GGGBB#B#B&&@B7. .?G@@@@@@@@@@@!                                          
//    :B#BBBBBB#&&&@G!   :#@@@@@@@@@@@BB&^                                         
//    ?#BBGGGBB&@@@?     ^@@@@@@@@@B5P..##.                                        
//    ?BBBBBBBB&@B7##GY^.^Y@@@&@#PG!.7JJ!??                                        
//    ^#BBBBBBB##^ J&@@@#@#5?Y7~?#B5:.^57?&7                                       
//     7B#BBBBB&7   .:!G&@P~7?Y77GY!7..B@@@@7                                      
//      ~PBBBG@J        G@@BJ7~?@! Y@Y.B&J?GG                                      
//        !YP@P         #@&&GY5B@YP@#5?BB?75:                                      
//          .~.        ^@P^:75JB@&@@JY!J&B?:                                       
//                     Y@P?!:!^P@@@@&G5PPG@#??GG^                                  
//                    .#@@@#??5#@@@#77. .^J#5Y&&B^                                 
//                     :?YP&@@@@@@@7: ^P^ .?G5GJ!YJ^                               
//                        YY#@@@@@@5: .!..:YG77!?77GB^                             
//                       ^@@&@@@@@@@B77~!YBBJB#G??~5@!                             
//                        J@@@@@@@@@@B#B#BJJB@@@@&@@@!         ~Y5^                
//                        5@@@@@@@@@5~^??P~~J@@@@#?G&G~.^^:. ~G@@@B                
//                        :B@&B@@@@@#?JJ^!!^GBGP5Y7?#7::G5!JB@&GPYP~^PG?.          
//                         5@#P#@@@@@@@@GJ!Y#&PY7?G7~77??^. 5@@GYJJ?B5PGP          
//                          Y&PY@@@@@@@@@@@@@@@@JB5Y^7!~~!!!B@5PBG@#P~:^^          
//                          .&PY5&@@@@@@@@@@@@J^!&P&BG^:.:?@P5!^! J!PBJYPBP?       
//                           BGP75#&@@@@@@@@@? .~@Y^^?7JP&#?^ . .  :^!&BYB^75G5~   
//                           Y#YG7Y##@@@@@@#5?P#&B~!!7^.7@B~:  5&J .:7B^Y!Y@@@@@!  
//                           7@?#577&&&@@@@@@@@@@BPPG?7Y#@B7.  ^!. .^5&BJ?&@@P@J.  
//                           !@JPG5J^B@@@@@@@@@@@@@@@@@@@@@BJ^ . : ??&@Y^~?Y#~577  
//                           7@P7@JGP:J@@@@@@@@@@@@@@@@@@@@@@PGJ!#5&@@5..!5J7???!  
//                           5@B^@&~##^^G@@@@@@@@@@@@@@@@@@@@@@@@@@@@@#^:!J??5@@#  
//                           ~!!.!7::7~  !!!!!!!!!!!!!!!!!!!!!!!!!!!!!7~:.. ^.!!~  
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/cryptography/MerkleProof.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/Address.sol";

contract IshoDolls is ERC721, Ownable, ReentrancyGuard {
   using Address for address payable;
   
   uint256 public constant MAX_SUPPLY = 1000;
   uint256 public constant PUBLIC_PRICE = 0.01 ether;
   uint256 public constant TIER2_PRICE = 0.0088 ether; // 10-19 mints
   uint256 public constant TIER3_PRICE = 0.0075 ether; // 20 mints
   uint256 public constant MAX_FREE_MINTS = 100;
   uint256 public constant MAX_BATCH_SIZE = 20;
   
   uint256 public totalSupply;
   uint256 public freeMintsUsed;
   
   bytes32 public merkleRoot;
   string private _baseTokenURI;
   bool public mintActiveManual = false;
   uint256 public mintStartTime = 0; // 0 means not set
   
   mapping(address => bool) public hasClaimedFree;
   
   event MerkleRootUpdated(bytes32 newRoot);
   event MintStatusChanged(bool isActive);
   event MintStartTimeSet(uint256 startTime);
   event OwnerMint(address indexed to, uint256 tokenId);
   
    constructor(
        string memory baseURI,
        bytes32 _merkleRoot
    ) ERC721("Isho Dolls", "ISHO") Ownable(msg.sender) {
        _baseTokenURI = baseURI;
        merkleRoot = _merkleRoot;
    }
   
   modifier mintIsActive() {
       require(isMintActive(), "Minting is not active");
       _;
   }
   
   // Check if minting is active (either manually opened or auto-opened by timestamp)
   function isMintActive() public view returns (bool) {
       if (mintActiveManual) {
           return true;
       }
       if (mintStartTime > 0 && block.timestamp >= mintStartTime) {
           return true;
       }
       return false;
   }
   
   // Calculate total cost based on quantity tiers
   function calculateTotalCost(uint256 quantity) public pure returns (uint256) {
       require(quantity > 0 && quantity <= MAX_BATCH_SIZE, "Invalid quantity");
       
       if (quantity < 10) {
           return quantity * PUBLIC_PRICE;
       } else if (quantity < 20) {
           return quantity * TIER2_PRICE;
       } else {
           return quantity * TIER3_PRICE;
       }
   }
   
   // Free mint for whitelisted addresses
   function freeMint(bytes32[] calldata merkleProof) external nonReentrant mintIsActive {
       require(totalSupply < MAX_SUPPLY, "Max supply reached");
       require(freeMintsUsed < MAX_FREE_MINTS, "All free mints claimed");
       require(!hasClaimedFree[msg.sender], "Already claimed free mint");
       
       // Verify merkle proof
       bytes32 leaf = keccak256(abi.encodePacked(msg.sender));
       require(
           MerkleProof.verify(merkleProof, merkleRoot, leaf),
           "Invalid merkle proof"
       );
       
       hasClaimedFree[msg.sender] = true;
       freeMintsUsed++;
       
       uint256 tokenId = totalSupply;
       totalSupply++;
       
       _safeMint(msg.sender, tokenId);
   }
   
    // Public mint (single)
    function publicMint() external payable mintIsActive {
        publicMintBatch(1);
    }

   
    // Public mint (batch)
    function publicMintBatch(uint256 quantity) public payable nonReentrant mintIsActive {
        require(quantity > 0 && quantity <= MAX_BATCH_SIZE, "Invalid quantity");
        require(totalSupply + quantity <= MAX_SUPPLY, "Would exceed max supply");
        
        uint256 totalCost = calculateTotalCost(quantity);
        require(msg.value >= totalCost, "Insufficient payment");
        
        for (uint256 i = 0; i < quantity; i++) {
            uint256 tokenId = totalSupply;
            totalSupply++;
            _safeMint(msg.sender, tokenId);
        }
        
        // Refund excess payment
        if (msg.value > totalCost) {
            payable(msg.sender).transfer(msg.value - totalCost);
        }
    }
   
   // Owner functions
   function ownerMint(address to) external onlyOwner {
       require(totalSupply < MAX_SUPPLY, "Max supply reached");
       
       uint256 tokenId = totalSupply;
       totalSupply++;
       
       _safeMint(to, tokenId);
       emit OwnerMint(to, tokenId);
   }
   
   function ownerMintBatch(address[] calldata recipients) external onlyOwner {
       require(totalSupply + recipients.length <= MAX_SUPPLY, "Would exceed max supply");
       
       for (uint256 i = 0; i < recipients.length; i++) {
           uint256 tokenId = totalSupply;
           totalSupply++;
           
           _safeMint(recipients[i], tokenId);
           emit OwnerMint(recipients[i], tokenId);
       }
   }
   
   function openMint() external onlyOwner {
       require(!mintActiveManual, "Minting is already manually active");
       mintActiveManual = true;
       emit MintStatusChanged(true);
   }
   
   function closeMint() external onlyOwner {
       require(mintActiveManual || isMintActive(), "Minting is already inactive");
       mintActiveManual = false;
       mintStartTime = 0; // Also clear any scheduled start time
       emit MintStatusChanged(false);
   }
   
   function setMintStartTime(uint256 _startTime) external onlyOwner {
       require(_startTime > block.timestamp, "Start time must be in the future");
       mintStartTime = _startTime;
       emit MintStartTimeSet(_startTime);
   }
   
   function clearMintStartTime() external onlyOwner {
       mintStartTime = 0;
       emit MintStartTimeSet(0);
   }
   
   function setMerkleRoot(bytes32 _merkleRoot) external onlyOwner {
       merkleRoot = _merkleRoot;
       emit MerkleRootUpdated(_merkleRoot);
   }
   
   function setBaseURI(string calldata baseURI) external onlyOwner {
       _baseTokenURI = baseURI;
   }
   
   function withdraw() external onlyOwner {
       uint256 balance = address(this).balance;
       require(balance > 0, "No funds to withdraw");
       
       payable(owner()).sendValue(balance);
   }
   
   // View functions
   function _baseURI() internal view virtual override returns (string memory) {
       return _baseTokenURI;
   }
   
   function isWhitelisted(address account, bytes32[] calldata merkleProof) 
       external 
       view 
       returns (bool) 
   {
       bytes32 leaf = keccak256(abi.encodePacked(account));
       return MerkleProof.verify(merkleProof, merkleRoot, leaf);
   }
   
   function remainingFreeMintsCount() external view returns (uint256) {
       return MAX_FREE_MINTS - freeMintsUsed;
   }
   
   function remainingSupply() external view returns (uint256) {
       return MAX_SUPPLY - totalSupply;
   }
   
   function timeUntilMintStart() external view returns (uint256) {
       if (mintStartTime == 0 || block.timestamp >= mintStartTime) {
           return 0;
       }
       return mintStartTime - block.timestamp;
   }
}