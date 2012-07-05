#
# Instance interface.
spawn         = require('child_process').spawn
net           = require 'net'

_             = require 'underscore'
async         = require 'async'

cf            = require 'config'
LithiumConfig = require('lithium_config').LithiumConfig

exports.Instance = class Instance
  config_path: LithiumConfig.server_class_path()

  constructor: (config, id, name, state, ip) ->
    @config = new cf.Config config if config?
    @id = id if id?
    @name = name if name?
    @state = state if state?
    @ip_address = ip if ip?

  # Create a server ready to run. Somewhere on the internet.  # Servers are created in the "stopped" state.
  @create: (config, callback) ->
    @config = new cf.Config config

  # Destroy a previously created server.
  @destroy: (instance, callback) ->

  # Get an instance by name
  @get: (name, callback) ->

  # List instances in the cloud
  @list: (callback) ->

  # Start the server. Immediately go into the 'starting' state,
  # and if everything goes okay, then sometime later it will be
  # in the 'running' state.
  start: (callback) ->

  # Stop the server. Immediately go into the 'stopping' state,
  # and if everything goes okay, then sometime later it will be
  # in the 'stopped' state.
  stop: (callback) ->

  # Return the state of the server.  Will be one of:
  # 'stopped', 'running', 'starting', 'stopping', and probably
  # others.
  state: (callback) ->

  # Run a shell command as root on the server.
  sh: (command, callback) ->
    @_ssh LithiumConfig.sshkey_private, command, callback

  # Copy files to the instance
  cp: (files, callback) ->
    if files.length > 0
      @_scp LithiumConfig.sshkey_private, files, callback
    else callback

  # Copy & run hooks on instance
  # TODO: coupled
  # TODO: we don't actually test this
  run_hooks: (callback) ->
    c = @config
    all_parents = while c.parent?
      c = c.parent
    all_parents = all_parents.reverse()
    configs = all_parents.concat @config
    configs = _.select configs, (c) -> c.hooks.length > 0
    async.forEachSeries configs, @run_config_hooks, callback

  run_config_hooks: (config, callback) =>
    console.log "Running hooks for #{config.name}"
    files_to_cp = _.select config.hooks, (hook) ->
      /^\d+_.+\.r\.\w/.test hook

    files_to_cp = _.map files_to_cp, (f) =>
      "#{@config_path}/#{config.name}/hooks/#{f}"
    @cp files_to_cp, (exit_code) =>
      callback if exit_code > 0
      hooks = _.map config.hooks, (h) ->
        {config_name: config.name, file: h}
      async.forEachSeries hooks, @_call_hook, callback


  #### Private methods ####

  _call_hook: (hook, callback) =>
    console.log "Running #{hook.file}"
    if /^\d+_.+\.r\.\w/.test hook.file
      @sh "sh /root/#{hook.file}", callback
    if /^\d+_.+\.l\.\w/.test hook.file
      @_local_sh "#{@config_path}/#{hook.config_name}/hooks/#{hook.file}", [@name], callback

  # Connect via SSH and execute command
  # TODO: proper callbacks?
  _ssh: (key, command, callback) ->
    @_wait_for_sshd key, =>
      args = [
        '-o', 'LogLevel=ERROR', '-o', 'UserKnownHostsFile=/dev/null', '-o', 'StrictHostKeyChecking=no', '-i', key, "root@#{@ip_address}", '-o', 'IdentitiesOnly=yes' ]
      args = args.concat command.split ' '

      ssh = spawn 'ssh', args
      ssh.stdout.on 'data', (data) -> process.stdout.write '[1;32mssh[0m: ' + data.toString('ascii')
      ssh.stderr.on 'data', (data) -> process.stderr.write '[1;31mssh[0m: ' + data.toString('ascii')
      ssh.on 'exit', callback

  # Copy files via SCP
  # TODO: factor out into SSH & SCP class, proper callbacks?
  _scp: (key, files, callback) ->
    @_wait_for_sshd key, =>
      args = [
        '-o', 'LogLevel=ERROR', '-o', 'UserKnownHostsFile=/dev/null', '-o', 'StrictHostKeyChecking=no', '-o', 'IdentitiesOnly=yes', '-i', key ]
      args = args.concat files
      args.push "root@#{@ip_address}:/root"

      ssh = spawn 'scp', args
      ssh.stdout.on 'data', (data) -> console.log data.toString('ascii')
      ssh.stderr.on 'data', (data) -> console.log data.toString('ascii')
      ssh.on 'exit', callback

  # Wait until we can connect to ssh and run the command "exit 99".
  _wait_for_sshd: (key, callback) ->
    again = =>
      args = [
        '-o', 'LogLevel=ERROR', '-o', 'UserKnownHostsFile=/dev/null', '-o', 'StrictHostKeyChecking=no', '-i', key, "root@#{@ip_address}", '-o', 'IdentitiesOnly=yes' ]
      args = args.concat "exit 99"
      ssh = spawn 'ssh', args
      ssh.stdout.on 'data', (data) -> process.stdout.write '[1;32mssh?[0m: ' + data.toString('ascii')
      ssh.stderr.on 'data', (data) -> process.stderr.write '[1;31mssh?[0m: ' + data.toString('ascii')
      ssh.on 'exit', (rc) ->
        if rc == 99
          callback()
        else
          setTimeout again, 999
    again()

  # Spawn a command locally, needs to be executable
  # TODO: put somewhere more sane, name it properly: exec?
  _local_sh: (command, args, callback) ->
    cmd = spawn command, args
    cmd.stdout.on 'data', (data) -> console.log data.toString('ascii')
    cmd.stderr.on 'data', (data) -> console.log data.toString('ascii')
    cmd.on 'exit', callback
