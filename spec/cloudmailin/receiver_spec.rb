require File.expand_path(File.dirname(__FILE__) + '/../spec_helper')
require 'multi_mail/cloudmailin/receiver'

describe MultiMail::Receiver::Cloudmailin do
  describe '#initialize' do
    it 'should raise an error if :http_post_format is missing' do
      expect{ MultiMail::Receiver.new :provider => :cloudmailin }.to raise_error(ArgumentError)
      expect{ MultiMail::Receiver.new :provider => :cloudmailin, :http_post_format => nil }.to raise_error(ArgumentError)
    end
  end

  context 'after initialization' do
    %w(multipart json raw).each do |http_post_format|
      let :http_post_format do
        http_post_format
      end

      def params(fixture)
        MultiMail::Receiver::Cloudmailin.parse(response("cloudmailin/#{http_post_format}", fixture))
      end

      before :all do
        @service = MultiMail::Receiver.new({
          :provider => :cloudmailin,
          :http_post_format => http_post_format,
        })
      end

      describe '#transform' do
        it 'should return a mail message' do
          pending
          message = @service.transform(params('valid'))[0]

          # Headers
          message.date.should    == DateTime.parse('Mon, 14 Apr 2013 20:55:30 -04:00')
          message.from.should    == ['james@opennorth.ca']
          message.to.should      == ['foo+bar@multimail.mailgun.org']
          message.subject.should == 'Test'

          # Body
          message.multipart?.should            == true
          message.parts.size.should            == 4
          message.parts[0].content_type.should == 'text/plain'
          message.parts[0].body.should         == "bold text\n\n> multiline\n> quoted\n> text\n\n\n--\nSignature block\n"
          message.parts[1].content_type.should == 'text/html; charset=UTF-8'
          message.parts[1].body.should         == %(<html><head></head><body style="word-wrap: break-word; -webkit-nbsp-mode: space; -webkit-line-break: after-white-space; "><b>bold text</b><div><br></div><div><blockquote type="cite">multiline</blockquote><blockquote type="cite">quoted</blockquote><blockquote type="cite">text</blockquote></div><div><br></div><div>--</div><div>Signature block</div><div></div></body></html><html><body style="word-wrap: break-word; -webkit-nbsp-mode: space; -webkit-line-break: after-white-space; "><head></head><div></div></body></html><html><head></head><body style="word-wrap: break-word; -webkit-nbsp-mode: space; -webkit-line-break: after-white-space; "><div></div></body></html>)

          # Attachments
          message.attachments[0].filename.should == 'foo.txt'
          message.attachments[0].read.should == "Lorem ipsum dolor sit amet, consectetur adipiscing elit. Sed fringilla consectetur rhoncus. Nunc mattis mattis urna quis molestie. Quisque ut mattis nisl. Donec neque felis, porta quis condimentum eu, pharetra non libero.\n"
          message.attachments[1].filename.should == 'bar.txt'
          message.attachments[1].read.should == "Nam accumsan euismod eros et rhoncus. Phasellus fermentum erat id lacus egestas vulputate. Pellentesque eu risus dui, id scelerisque neque. Cum sociis natoque penatibus et magnis dis parturient montes, nascetur ridiculus mus.\n"

          # Extra Cloudmailin parameters
          message['reply_plain'].value.should == 'bold text' unless http_post_format == 'raw'
          message['X-Mailgun-Spf'].value.should == 'pass'
        end
      end

      describe '#spam?' do
        it 'should return true if the response is spam' do
          pending
          message = @service.transform(params('spam'))[0]
          @service.spam?(message).should == true
        end

        it 'should return false if the response is ham' do
          pending
          message = @service.transform(params('valid'))[0]
          @service.spam?(message).should == false
        end
      end
    end
  end
end
