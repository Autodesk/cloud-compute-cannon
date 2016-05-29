class Fluent::HTTPOutput < Fluent::Output
  Fluent::Plugin.register_output('url_callback', self)

  def initialize
    super
    require 'net/http'
    require 'uri'
  end

  def configure(conf)
    super
  end

  def start
    super
  end

  def shutdown
    super
  end

  def handle_record(tag, time, record)
    begin
      url = URI.parse(record["url"])
      req = Net::HTTP::Get.new(url.to_s)
      res = Net::HTTP.start(url.host, url.port) {|http|
        http.request(req)
      }
      puts record["url"] + " => " + res.body
    rescue
      puts $!
    end
  end

  def emit(tag, es, chain)
    es.each do |time, record|
      puts "sdfsdfsdfsdf"
      puts tag
      puts record
      handle_record(tag, time, record)
    end
    chain.next
  end
end