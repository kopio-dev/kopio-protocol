// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

contract MarketStatus is Ownable {
    error NotAllowed(address who);
    error InvalidInput();
    error InvalidTicker(bytes32 ticker);
    error InvalidExchange(bytes32 exchange);

    // allowed addresses
    mapping(address => bool) public allowed;

    // maps tickers to its exchange, eg. "SPY" => "NASDAQ"
    mapping(bytes32 => bytes32) public exchangeOf;
    // maps exchange => 1 or 2 (closed/open)
    mapping(bytes32 => uint256) public status;

    modifier onlyAllowed() {
        if (!allowed[msg.sender]) {
            revert NotAllowed(msg.sender);
        }
        _;
    }

    event StatusSet(bytes32[] indexed exchanges, bool[] status);
    event AllowedSet(address indexed who, bool allowed);
    event TickersSet(bytes32[] indexed tickers, bytes32[] indexed exchanges);

    /// @notice deploy with preselected tickers + exchanges
    /// @dev they are set to false by default
    /// @param _tickers tickers to track. ex: AAPL => "AAPL"
    /// @param _exchanges The bytes32 exchanges to be track. ex: NASDAQ => bytes32("NASDAQ")
    /// @param _owner The owner of the contract
    constructor(bytes32[] memory _tickers, bytes32[] memory _exchanges, address _owner) Ownable(_owner) {
        allowed[_owner] = true;
        _setStatus(_exchanges, new bool[](_exchanges.length));
        _setTickers(_tickers, _exchanges);
    }

    /// @notice Set the allowed status of an address
    /// @dev Only the owner can call this function
    /// @param _who The address to set the allowed status
    /// @param _allowed The allowed status
    function setAllowed(address _who, bool _allowed) external onlyOwner {
        allowed[_who] = _allowed;
        emit AllowedSet(_who, _allowed);
    }

    /// @notice Gelato function, Set the status of the exchanges
    /// @dev Only the owner or gelato can call this function
    /// @param _exchanges The exchanges to set the status. ex: bytes32("NASDAQ")
    /// @param _status The status of the exchanges. true for open, false for closed
    function setStatus(bytes32[] calldata _exchanges, bool[] calldata _status) external onlyAllowed {
        _setStatus(_exchanges, _status);
    }

    // Admin functions

    /// @notice Set the tickers and exchanges
    /// @dev Only the owner can call this function
    /// @param _tickers The hashed tickers to track. ex: AAPL => bytes32("AAPL")
    /// @param _exchanges The hashed exchanges to be track. ex: NASDAQ => bytes32("NASDAQ")
    function setTickers(bytes32[] memory _tickers, bytes32[] memory _exchanges) external onlyOwner {
        _setTickers(_tickers, _exchanges);
    }

    function _setStatus(bytes32[] memory _exchanges, bool[] memory _status) internal {
        uint256 length = _exchanges.length;
        if (length != _status.length) revert InvalidInput();

        for (uint256 i; i < length; ) {
            status[_exchanges[i]] = _status[i] == true ? 2 : 1;
            unchecked {
                ++i;
            }
        }
        emit StatusSet(_exchanges, _status);
    }

    function _setTickers(bytes32[] memory _tickers, bytes32[] memory _exchanges) internal {
        uint256 length = _tickers.length;
        if (length != _exchanges.length) revert InvalidInput();

        for (uint256 i; i < length; ) {
            exchangeOf[_tickers[i]] = _exchanges[i];
            unchecked {
                ++i;
            }
        }
        emit TickersSet(_tickers, _exchanges);
    }

    // View functions

    /// @notice Get the status of the exchange
    /// @param exchange The exchange to get the status (ex bytes32("NASDAQ"))
    /// @return The status of the exchange
    function getExchangeStatus(bytes32 exchange) public view returns (bool) {
        uint256 currentStatus = status[exchange];
        if (currentStatus == 0) revert InvalidExchange(exchange);
        return currentStatus == 2;
    }

    /// @notice Get the exchange of the ticker
    /// @param ticker The ticker to get the exchange
    /// @return The exchange of the ticker (hashed ex keccak256("NASDAQ"))
    function getTickerExchange(bytes32 ticker) external view returns (bytes32) {
        bytes32 exchange = exchangeOf[ticker];
        if (exchange == 0x0) revert InvalidTicker(ticker);
        return exchange;
    }

    /// @notice Get the status of the ticker
    /// @param ticker The ticker to get the status (ex AAPL)
    /// @return The status of the ticker
    function getTickerStatus(bytes32 ticker) public view returns (bool) {
        bytes32 exchange = exchangeOf[ticker];
        if (exchange == 0x0) revert InvalidTicker(ticker);
        return status[exchange] == 2;
    }

    /// @notice Get the status of the exchanges
    /// @param _exchanges The exchanges to get the status
    /// @return The status of the exchanges
    function getExchangeStatuses(bytes32[] calldata _exchanges) external view returns (bool[] memory) {
        uint256 length = _exchanges.length;
        bool[] memory statuses = new bool[](length);
        for (uint256 i; i < length; ) {
            statuses[i] = getExchangeStatus(_exchanges[i]);
            unchecked {
                ++i;
            }
        }
        return statuses;
    }

    /// @notice Get the status of the tickers
    /// @param _tickers The tickers to get the status
    /// @return The status of the tickers
    function getTickerStatuses(bytes32[] memory _tickers) external view returns (bool[] memory) {
        uint256 length = _tickers.length;
        bool[] memory statuses = new bool[](length);
        for (uint256 i; i < length; ) {
            statuses[i] = getTickerStatus(_tickers[i]);
            unchecked {
                ++i;
            }
        }
        return statuses;
    }
}
