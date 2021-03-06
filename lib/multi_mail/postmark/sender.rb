module MultiMail
  module Sender
    # Postmark's outgoing mail sender.
    class Postmark
      include MultiMail::Sender::Base

      requires :api_key

      attr_reader :api_key

      # Initializes a Postmark outgoing email sender.
      #
      # @param [Hash] options required and optional arguments
      # @option options [String] :api_key a Postmark API key
      # @see http://developer.postmarkapp.com/developer-build.html#authentication-headers
      def initialize(options = {})
        super
        @api_key = settings.delete(:api_key)
      end

      # Returns the additional parameters for the API call.
      #
      # @return [Hash] the additional parameters for the API call
      def parameters
        parameters = settings.dup
        parameters.delete(:return_response)

        if tracking.key?(:opens)
          parameter = :TrackOpens
          case tracking[:opens]
          when true, false, nil
            parameters[parameter] = tracking[:opens]
          when 'yes'
            parameters[parameter] = true
          when 'no'
            parameters[parameter] = false
          end # ignore "htmlonly"
        end

        parameters
      end

      # Delivers a message via the Postmark API.
      #
      # @param [Mail::Message] mail a message
      # @see http://developer.postmarkapp.com/developer-build.html
      # @see http://developer.postmarkapp.com/developer-build.html#http-response-codes
      # @see http://developer.postmarkapp.com/developer-build.html#api-error-codes
      def deliver!(mail)
        message = MultiMail::Message::Postmark.new(mail).to_postmark_hash.merge(parameters)

        response = Faraday.post do |request|
          request.url 'https://api.postmarkapp.com/email'
          request.headers['Accept'] = 'application/json'
          request.headers['Content-Type'] = 'application/json'
          request.headers['X-Postmark-Server-Token'] = @api_key
          request.body = JSON.dump(message)
        end

        body = JSON.load(response.body)

        unless response.status == 200
          case body['ErrorCode']
          when 10
            raise InvalidAPIKey, body['Message']
          when 300
            case body['Message']
            when "Header 'Content-Type' not allowed."
              raise InvalidHeader, body['Message']
            when "Header 'Date' not allowed."
              raise InvalidHeader, body['Message']
            when "Invalid 'From' value."
              raise MissingSender, body['Message']
            when 'Zero recipients specified'
              raise MissingRecipients, body['Message']
            when 'Provide either email TextBody or HtmlBody or both.'
              raise MissingBody, body['Message']
            else
              raise InvalidMessage, body['Message']
            end
          else
            raise InvalidRequest, body['Message']
          end
        end

        if settings[:return_response]
          body
        else
          self
        end
      end
    end
  end
end
