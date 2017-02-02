# encoding: utf-8
require 'logstash/inputs/protocols/protocol'
require 'date'

class EthereumProtocol < BlockchainProtocol

  BLOCK_NUM_KEYS = %w(number difficulty totalDifficulty size gasLimit gasUsed timestamp)
  TX_NUM_KEYS = %w(nonce blockNumber transactionIndex gasPrice gas)

  def initialize(host, port, user, pass, logger)
    super(host, port, nil, nil, logger)
  end

  # returns a JSON body to be sent to the Ethereum JSON-RPC endpoint
  def get_post_body(name, params)
    { 'method' => name, 'params' => params, 'id' => '1', 'jsonrpc' => '2.0' }
  end

  # returns the latest block number
  public
  def get_block_count
    begin
      make_rpc_call('eth_blockNumber').to_decimal
    rescue JSONRPCError, java.lang.Exception => e
      @logger.warn? && @logger.warn('Could not find latest block count', :exc => e)
    end
  end

  # returns the block at the given height
  public
  def get_block(height)
    # get the block data
    block_data = make_rpc_call('eth_getBlockByNumber', height, true)

    # get all transaction data
    tx_info = block_data.delete('transactions')

    # unhex numbers and strings
    unhex(block_data, BLOCK_NUM_KEYS)
    tx_info.each do |tx|
      unhex(tx, TX_NUM_KEYS)
    end

    timestamp = Time.at(block_data['timestamp']).utc.to_datetime.iso8601(3)

    return block_data, tx_info, timestamp
  end # def get_block

  def unhex(data, num_keys)
    data.each do |key, value|
      next if value.kind_of?(Array)

      if num_keys.include? key
        data[key] = value.to_decimal()
      else
        data[key] = value.to_string()
      end
    end
  end
end

class String
  def to_decimal
    self.convert_base(16, 10)
  end

  def to_string
    self.convert_base(16, 16)
  end

  def convert_base(from, to)
    conv = self.to_i(from).to_s(to)
    to == 10 && conv.to_i <= 9223372036854775807 ? conv.to_i : conv
  end
end
