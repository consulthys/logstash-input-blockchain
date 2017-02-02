# encoding: utf-8
require 'net/http'
require 'uri'
require 'json'

class BlockchainProtocol
  def initialize(host, port, user, pass)
    @http = Net::HTTP.new(host, port)
    @user = user
    @password = pass
  end

  # returns the block at the given height
  # (to be implemented in subclasses)
  public
  def get_block(height)
    return nil, nil, nil
  end # def get_block

  # returns the latest block number
  # (to be implemented in subclasses)
  public
  def get_block_count
    return 0
  end

  # returns a JSON body to be sent to the JSON-RPC endpoint
  # (to be implemented in subclasses)
  def get_post_body(name, params)
    {}
  end

  public
  def make_rpc_call(name, *args)
    post_body = get_post_body(name, args).to_json
    resp = JSON.parse( http_post_request(post_body) )
    raise JSONRPCError, resp['error'] if resp['error']
    resp['result']
  end # def method_missing

  def http_post_request(post_body)
    request = Net::HTTP::Post.new("/")
    request.basic_auth @user, @password if @user != nil && @password != nil
    request.content_type = 'application/json'
    request.body = post_body
    @http.request(request).body
  end # def http_post_request
end

class JSONRPCError < RuntimeError; end
