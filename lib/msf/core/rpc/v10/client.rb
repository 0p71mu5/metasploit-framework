# -*- coding: binary -*-
require 'xmlrpc/client'
require 'msgpack'

require 'rex'
require 'rex/proto/http'

require 'msf/core/rpc/v10/constants'

module Msf
module RPC

class Client

  # @return [String] A login token.
  attr_accessor :token

  # @return [Hash] Login information.
  attr_accessor :info


  # Initializes the RPC client to connect to: https://127.0.0.1:3790 (TLS1)
  #
  # @param [Hash] info Information needed for the initialization.
  # @option info [String] :token A token used by the client.
  # @return [void]
  def initialize(info={})
    self.info = {
      :host => '127.0.0.1',
      :port => 3790,
      :uri  => '/api/',
      :ssl  => true,
      :ssl_version => 'TLS1',
      :context     => {}
    }.merge(info)

    self.token = self.info[:token]
  end


  # Logs in by calling the 'auth.login' API.
  #
  # @param [String] user Username.
  # @param [String] pass Password.
  # @raise RuntimeError Indicating a failed authentication.
  # @return [TrueClass] Indicating a successful login.
  def login(user,pass)
    res = self.call("auth.login", user, pass)
    unless (res && res['result'] == "success")
      raise RuntimeError, "authentication failed"
    end
    self.token = res['token']
    true
  end


  # Calls an API.
  #
  # @param [String] meth The RPC API to call.
  # @param [Array] args The arguments to pass.
  # @raise [RuntimeError] Something is wrong while calling the remote API, including:
  #                       * A missing token (your client needs to authenticate).
  #                       * A unexpected response from the server, such as a timeout or unexpected HTTP code.
  # @raise [Msf::RPC::ServerException] The RPC service returns an error.
  # @return [Hash] The API response.
  # @example
  #  # This will return something like this:
  #  # {"version"=>"4.11.0-dev", "ruby"=>"2.1.5 x86_64-darwin14.0 2014-11-13", "api"=>"1.0"}
  #  rpc.call('core.version')
  def call(meth, *args)
    unless meth == "auth.login"
      unless self.token
        raise RuntimeError, "client not authenticated"
      end
      args.unshift(self.token)
    end

    args.unshift(meth)

    unless @cli
      @cli = Rex::Proto::Http::Client.new(info[:host], info[:port], info[:context], info[:ssl], info[:ssl_version])
      @cli.set_config(
        :vhost => info[:host],
        :agent => "Metasploit RPC Client/#{API_VERSION}",
        :read_max_data => (1024*1024*512)
      )
    end

    req = @cli.request_cgi(
      'method' => 'POST',
      'uri'    => self.info[:uri],
      'ctype'  => 'binary/message-pack',
      'data'   => args.to_msgpack
    )

    res = @cli.send_recv(req)
    @cli.close

    if res && [200, 401, 403, 500].include?(res.code)
      resp = MessagePack.unpack(res.body)

      # Boolean true versus truthy check required here;
      # RPC responses such as { "error" => "Here I am" } and { "error" => "" } must be accommodated.
      if resp && resp.kind_of?(::Hash) && resp['error'] == true
        raise Msf::RPC::ServerException.new(resp['error_code'] || res.code, resp['error_message'] || resp['error_string'], resp['error_class'], resp['error_backtrace'])
      end

      return resp
    else
      raise RuntimeError, res.inspect
    end
  end


  # Closes the client.
  #
  # @return [void]
  def close
    if @cli && @cli.conn?
      @cli.close
    end
    @cli = nil
  end

end
end
end

