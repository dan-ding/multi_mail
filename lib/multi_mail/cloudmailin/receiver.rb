module MultiMail
  module Receiver
    # Cloudmailin's incoming email receiver.
    class Cloudmailin < MultiMail::Service
      include MultiMail::Receiver::Base

      recognizes :http_post_format
      attr_reader :http_post_format

      # Initializes a Cloudmailin incoming email receiver.
      #
      # @param [Hash] options required and optional arguments
      # @option options [String] :http_post_format "multipart", "json" or "raw"
      def initialize(options = {})
        super
        @http_post_format = options[:http_post_format]
      end

      # @param [Hash] params the content of Cloudmailin's webhook
      # @return [Boolean] whether the request originates from Cloudmailin
      # @see http://docs.cloudmailin.com/receiving_email/securing_your_email_url_target/
      def valid?(params)
        true
      end

      # @param [Hash] params the content of Cloudmailin's webhook
      # @return [Array<Mail::Message>] messages
      # @see http://docs.cloudmailin.com/http_post_formats/multipart/
      # @see http://docs.cloudmailin.com/http_post_formats/json/
      # @see http://docs.cloudmailin.com/http_post_formats/raw/
      # @todo Handle cases where the attachment store is in-use.
      def transform(params)
        # Must make `http_post_format` a local variable to satisfy Mail's scope.
        x = http_post_format

        case http_post_format
        when 'raw', '', nil
          message = Mail.new(params['message'])

          # @todo The preambles and epilogues of nested parts may be lost.
          # @see https://github.com/mikel/mail/blob/master/spec/mail/body_spec.rb
          if message.multipart? && message.parts.any?(&:multipart?)
            # Get the message parts as a flat array.
            flat = flatten(Mail.new, message.parts.dup)

            # Rebuild the message's parts.
            message.parts.clear

            # Merge non-attachments with the same content type.
            (flat.parts - flat.attachments).group_by(&:content_type).each do |content_type,group|
              message.parts << Mail::Part.new({
                :content_type => content_type,
                :body => group.map{|part| part.body.decoded}.join,
              })
            end

            # Add attachments last.
            flat.attachments.each do |part|
              message.parts << part
            end
          end

          # Re-use Mailgun headers.
          message['X-Mailgun-Spf'] = params['envelope']['spf']['result']

          # Discard rest of `envelope`: `from`, `to`, `recipients`,
          # `helo_domain` and `remote_ip`.
          [message]
        when 'multipart', 'json'
          headers = Multimap.new
          params['headers'].each do |key,value|
            if Array === value
              value.each do |v|
                headers[key] = v
              end
            else
              headers[key] = value
            end
          end

          message = Mail.new do
            headers headers

            text_part do
              body params['plain']
            end

            if params.key?('html')
              html_part do
                content_type 'text/html; charset=UTF-8'
                body params['html']
              end
            end

            if params.key?('attachments')
              if x == 'json'
                params['attachments'].each do |attachment|
                  add_file(:filename => attachment['file_name'], :content => Base64.decode64(attachment['content']))
                end
              else
                params['attachments'].each do |_,attachment|
                  add_file(:filename => attachment[:filename], :content => attachment[:tempfile].read)
                end
              end
            end
          end

          # Extra Cloudmailin parameters. The multipart format uses CRLF whereas
          # the JSON format uses LF. Normalize to LF.
          message['reply_plain'] = params['reply_plain'].gsub("\r\n", "\n")
          message['X-Mailgun-Spf'] = params['envelope']['spf']['result']
          [message]
        else
          raise ArgumentError, "Can't handle Cloudmailin #{http_post_format} HTTP POST format"
        end
      end

      # @param [Mail::Message] message a message
      # @return [Boolean] whether the message is spam
      def spam?(message)
        message['X-Mailgun-Spf'] && message['X-Mailgun-Spf'].value == 'fail'
      end

    private

      # Flattens a hierarchy of message parts.
      #
      # @param [Mail::Message] message a message
      # @param [Mail::PartsList] parts parts to add to the message
      # @return [Mail::Message] the message with all the parts
      def flatten(message, parts)
        parts.each do |part|
          if part.multipart?
            flatten(message, part.parts)
          else
            message.parts << part
          end
        end
        message
      end
    end
  end
end