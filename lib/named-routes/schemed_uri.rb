module NamedRoutes
  class SchemedUri
    attr_reader :routes, :scheme

    def initialize(routes, scheme)
      @routes, @scheme = routes, scheme
    end

    def method_missing(method_name, *args, &block)
      is_http = routes.scheme.nil? || routes.scheme == "http"
      is_https = routes.scheme == "https"
      use_default_port = is_http && (routes.port.nil? || routes.port.to_s == "80")
      use_default_port |= is_https && (routes.port.nil? || routes.port.to_s == "443")
      port_suffix = ":#{routes.port}" unless use_default_port

      "#{scheme}://#{routes.host}#{port_suffix}#{routes.send(method_name, *args, &block)}"
    end
  end
end
