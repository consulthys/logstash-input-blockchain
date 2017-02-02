# encoding: utf-8
require 'logstash/inputs/protocols/protocol'
require 'date'

class BitcoinProtocol < BlockchainProtocol
  def initialize(host, port, user, pass)
    super(host, port, user, pass)
  end

  # returns a JSON body to be sent to the Bitcoin JSON-RPC endpoint
  def get_post_body(name, params)
    { 'method' => name, 'params' => params, 'id' => 'jsonrpc' }
  end

  # returns the latest block number
  public
  def get_block_count
    begin
      make_rpc_call('getblockcount')
    rescue JSONRPCError, java.lang.Exception => e
      p e
    end
  end

  # returns the block at the given height
  public
  def get_block(height)
    # get the corresponding hash for the given height
    block_hash = make_rpc_call("getblockhash", height)
    # get the block data
    block_data = make_rpc_call("getblock", block_hash)

    # get all transaction data
    tx_info = Array.new
    block_data['tx'].each { |txid|
      begin
        tx_hash = make_rpc_call("getrawtransaction", txid)
        tx = make_rpc_call("decoderawtransaction", tx_hash)
        tx_info << tx
      rescue JSONRPCError, java.lang.Exception => e
        #@logger.warn? && @logger.warn('Could not find any information about transaction', :tx => txid)
        p e
      end
    }
    timestamp =  Time.at(block_data['time']).utc.to_datetime.iso8601(3)

    return block_data, tx_info, timestamp
  end # def get_block
end