
fg = require 'fast-glob'
path = require 'path'
_ = require 'lodash'

extractRoutes = (opts) ->
  files = fg.sync [path.join opts.dir, '**/*.(js|ts|coffee)']

  routes = for file in files
    name = path.relative opts.dir, file
    name = name.substring 0, name.lastIndexOf '.'
    tokens = name.split path.sep

    extras = []
    fileName = _.last tokens
    method = if fileName.indexOf('.') > -1
      baseTokens = fileName.split '.'
      tokens[tokens.length - 1] = baseTokens[0]
      # excess .{---} to the left of .{method}.{ext} will be placed into an array
      extras = baseTokens[1...baseTokens.length - 1] if baseTokens.length > 2
      _.last baseTokens
    else 'get'

    # remove underscore only base names
    if tokens[tokens.length - 1] is '_'
      tokens.splice tokens.length - 1, 1

    # replace first-only underscores with path param :
    for token, index in tokens
      if token.indexOf('_') is 0
        tokens[index] = token.replace '_', ':'

    # add root base name if inclusive
    if opts.inclusive
      tokens.unshift path.basename cwd

    # return
    {
      path: "/#{tokens.join '/'}"
      module: require path.join process.cwd(), file
      file
      method
      extras
    }

handleRoute = (fastify, route, required, custom) ->
  # Function Mode
  if _.isFunction required
    unless custom
      fastify.route
        url: route.path
        method: (route.method or 'GET').toUpperCase()
        handler: do (required) ->
          (req, res) -> required.call @, req, res
    else
      fastify.route required route

  # Object mode
  else if _.isObject required
    obj = _.merge
      url: route.path
      method: (route.method or 'GET').toUpperCase()
      config: route: route
    , required
    return unless obj.handler?
    fastify.route obj

  else
    throw new Error 'Unsupported module type.'

module.exports = (fastify, opts, next) ->
  routes = extractRoutes opts

  # Start registering routes to fastify
  for route in routes
    required = route.module
    console.log "Adding route -- #{route.method.toUpperCase()} #{route.path}"
    # Static mode
    if _.some(route.extras, (x) -> x is 'static')
      fastify[route.method] routePath, (req, res) -> await required
      continue

    custom = _.some(route.extras, (x) -> x is 'custom')

    # Array mode
    if _.isArray required

      # Shorthand route call
      if _.isString required[0]
        fastify[route.method] required...

      # Custom Route per Element
      else
        for item in required
          handleRoute fastify, route, item, custom

    # Standard mode
    else
      handleRoute fastify, route, required, custom

  next()
