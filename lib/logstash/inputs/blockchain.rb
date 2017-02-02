# encoding: utf-8
require "logstash/inputs/base"
require "logstash/namespace"
require "stud/interval"
require "socket" # for Socket.gethostname

# This input plugin reads blocks from the specified blockchain.
# It currently supports both the Bitcoin and the Ethereum blockchain protocols.
# New protocols will be added in the future.
#

class LogStash::Inputs::Blockchain < LogStash::Inputs::Base

  require 'logstash/inputs/protocols/protocol'
  require 'logstash/inputs/protocols/bitcoin'
  require 'logstash/inputs/protocols/ethereum'

  config_name "blockchain"

  # If undefined, Logstash will complain, even if codec is unused.
  default :codec, "json"

  # The underlying blockchain protocol: "bitcoin" (default) or "ethereum"
  config :protocol, :validate => :string, :default => "bitcoin"

  # The host or ip of the RPC endpoint to bind to
  config :host, :validate => :string, :default => "127.0.0.1"

  # The TCP port of the RPC endpoint to bind to
  config :port, :validate => :number, :default => 8332

  # The username for basic authentication to the RPC endpoint
  config :user, :validate => :string, :required => false

  # The password for basic authentication to the RPC endpoint
  config :password, :validate => :string, :required => false

  # The height of the first block to fetch (defaults to 0, i.e. starts at the genesis block)
  config :start_height, :validate => :number, :default => 0

  # The granularity of the events to produce: "transaction" or "block" (default)
  config :granularity, :validate => :string, :default => "block"

  # Set how frequently blocks should be retrieved.
  # `1`, means retrieve one block every second.
  # The default, `0`, means retrieve one block immediately after the previous one has been retrieved (i.e. don't wait).
  config :interval, :validate => :number, :default => 0

  GRANULARITIES = %w(transaction block)
  PROTOCOLS = %w(bitcoin ethereum)

  public
  def register
    unless PROTOCOLS.include? @protocol
      @logger.error("Expected protocol to be one of #{PROTOCOLS}, got '#{@protocol}' instead, defaulting to 'bitcoin'")
      @protocol = 'bitcoin'
    end

    unless GRANULARITIES.include? @granularity
      @logger.error("Expected granularity to be one of #{GRANULARITIES}, got '#{@granularity}' instead, defaulting to 'block'")
      @granularity = 'block'
    end

    case @protocol
      when 'ethereum'
        @blockchain = EthereumProtocol.new(@host, @port, @user, @password, @logger)
      else
        @blockchain = BitcoinProtocol.new(@host, @port, @user, @password, @logger)
    end

    @logger.info('Setting up blockchain RPC client', :protocol => @protocol, :host => @host, :port => @port)
  end # def register

  def run(queue)
    # retrieve the latest block count
    latest_height = @blockchain.get_block_count()
    @logger.info('Retrieving latest block height', :height => latest_height)

    # adjust start height if necessary
    if @start_height > latest_height
      @start_height = latest_height
    elsif @start_height < 0
      @start_height = 0
    end
    @logger.info('Starting at block height', :height => @start_height)

    # start at specified block, or latest or genesis one
    current_height = @start_height

    # we can abort the loop if stop? becomes true
    while !stop?
      begin
        # get block and transaction data using the given protocol
        block_data, tx_info, timestamp = @blockchain.get_block(current_height)

        # add some information
        block_data['tx_count'] = tx_info.length

        @logger.debug? && @logger.debug('Found block', :height => current_height, :block => block_data)

        # enqueue events according to granularity
        case @granularity
          when 'transaction'
            tx_info.each { |tx|
              tx['@timestamp'] = timestamp
              tx['block'] = block_data
              enqueue(queue, tx)
            }
          else
            block_data['@timestamp'] = timestamp
            block_data['tx_info'] = tx_info
            enqueue(queue, block_data)
        end

      rescue JSONRPCError, java.lang.Exception => e
        @logger.error? && @logger.error('Error when making RPC call',
                                        :exception => e,
                                        :exception_message => e.message,
                                        :exception_backtrace => e.backtrace
        )
      end

      # go to the next block
      current_height += 1

      # because the sleep interval can be big, when shutdown happens
      # we want to be able to abort the sleep
      # Stud.stoppable_sleep will frequently evaluate the given block
      # and abort the sleep(@interval) if the return value is true
      Stud.stoppable_sleep(@interval) { stop? } unless @interval < 1
    end # loop
  end # def run

  def enqueue(queue, data)
    event = LogStash::Event.new(data)
    decorate(event)
    queue << event
  end # def enqueue

  def stop
  end
end # class LogStash::Inputs::Blockchain
