if defined?(Patron)

  module Patron
    class Session

      def handle_request_with_webmock(req)
        request_signature = build_request_signature(req)

        WebMock::RequestRegistry.instance.requested_signatures.put(request_signature)

        if WebMock.registered_request?(request_signature)
          webmock_response = WebMock.response_for_request(request_signature)
          handle_file_name(req, webmock_response)
          build_patron_response(webmock_response)
        elsif WebMock.net_connect_allowed?(request_signature.uri)
          handle_request_without_webmock(req)
        else
          message = "Real HTTP connections are disabled. Unregistered request: #{request_signature}"
          WebMock.assertion_failure(message)
        end
      end

      alias_method :handle_request_without_webmock, :handle_request
      alias_method :handle_request, :handle_request_with_webmock



      def handle_file_name(req, webmock_response)
        if req.action == :get && req.file_name
          begin
            File.open(req.file_name, "w") do |f|
              f.write webmock_response.body
            end
          rescue Errno::EACCES
            raise ArgumentError.new("Unable to open specified file.")
          end
        end
      end

      def build_request_signature(req)
        uri = Addressable::URI.heuristic_parse(req.url)
        uri.path = uri.normalized_path.gsub("[^:]//","/")
        uri.user = req.username
        uri.password = req.password

        if [:put, :post].include?(req.action)
          if req.file_name
            if !File.exist?(req.file_name) || !File.readable?(req.file_name)
              raise ArgumentError.new("Unable to open specified file.")
            end
            request_body = File.read(req.file_name)
          elsif req.upload_data
            request_body = req.upload_data
          else
            raise ArgumentError.new("Must provide either data or a filename when doing a PUT or POST")
          end
        end

        request_signature = WebMock::RequestSignature.new(
          req.action,
          uri.to_s,
          :body => request_body,
          :headers => req.headers
        )
        request_signature
      end

      def build_patron_response(webmock_response)
        raise Patron::TimeoutError if webmock_response.should_timeout        
        webmock_response.raise_error_if_any
        res = Patron::Response.new
        res.instance_variable_set(:@body, webmock_response.body)
        res.instance_variable_set(:@status, webmock_response.status[0])
        res.instance_variable_set(:@status_line, webmock_response.status[1])
        res.instance_variable_set(:@headers, webmock_response.headers)
        res
      end

    end
  end

end
