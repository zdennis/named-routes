require 'active_support/core_ext/hash/indifferent_access'

module NamedRoutes
  class Error < ::StandardError ; end

  class Routes
    class_attribute :host, :prefix, :scheme, :port

    def self.uri=(uri)
      self.host = uri.host
      self.port = uri.port
      self.scheme = uri.scheme
    end

    module Definition
      extend NamedRoutes::Concern

      def eval(*args)
        self.class.eval(*args)
      end

      def as_json(*args)
        self.class.defined_routes
      end

      module ClassMethods
        def instance
          @instance ||= new
        end

        def http
          SchemedUri.new(self, "http")
        end

        def https
          SchemedUri.new(self, "https")
        end

        def route(name, definition, include_prefix=true)
          full_definition = eval(definition, {}, :prefix => include_prefix)
          (_defined_routes[name.to_s] ||= []) << full_definition
          define_method name do |*args|
            #
            # This does an exact match on the when determining which route
            # definition to use or it will fall back to a best match. It's all
            # based on the defined params and the passed in params.
            #
            best_match = [full_definition, -1]
            params_to_match = (args.first || {}).keys.map(&:to_s).sort
            matching_definition = self.class.defined_routes[name.to_s].detect do |path|
              if params_to_match == path.scan(/:(\w+)/).flatten.sort
                path
              else
                matched_count = params_to_match.reduce(0) do |count,param|
                  count += 1 if path =~ /:#{param}/
                  count
                end
                best_match = [path, matched_count] if matched_count > best_match.last
                nil
              end
            end
            matching_definition ||= best_match.first
            self.class.eval(matching_definition, [args.first].compact.first || {})
          end
          define_method "#{name}_path" do |*args|
            send(name, *args)
          end
          define_method "#{name}_url" do |*args|
            if self.class.host.nil?
              raise Error, "A :host must be set in order to generate a URL"
            end
            SchemedUri.new(self, self.class.scheme || "http").send name, *args
          end

          yield full_definition if block_given?
          full_definition
        end
        alias_method :path, :route
        alias_method :uri, :route

        def defined_routes
          (ancestors.reverse + [self]).inject({}) do |memo, klass|
            memo.merge!(klass._defined_routes) if klass.respond_to?(:_defined_routes)
            memo
          end
        end

        def _defined_routes
          @_defined_routes ||= {}
        end

        def eval(definition, params_arg={}, options={})
          full_definition = (options[:prefix] && prefix) ? File.join("", prefix, definition) : definition
          params = params_arg.with_indifferent_access
          uri_string = if params.empty?
            full_definition
          else
            full_definition.split("/").map do |segment|
              segment_value = segment[/^:(.*)/, 1]
              segment_value_parts = segment_value.to_s.split(".")
              segment_name = segment_value_parts[0]
              if segment_name
                param_name = params.delete(File.basename(segment_name, '.*').to_s)
                URI.escape([param_name, *segment_value_parts[1..-1]].join("."))
              else
                segment
              end
            end.join("/")
          end
          unless params.empty?
            uri_string << "?#{params.to_param.gsub("%5B", "[").gsub("%5D", "]")}"
          end
          uri_string
        end

        def normalize(uri)
          uri.gsub(Regexp.new("^#{File.join("", prefix.to_s)}"), "/").gsub("//", "/")
        end

        def as_json(*args)
          instance.as_json(*args)
        end

        def method_missing(method_name, *args, &block)
          if instance.respond_to?(method_name)
            instance.send(method_name, *args, &block)
          else
            super
          end
        end
      end
    end
    include Definition
  end
end
