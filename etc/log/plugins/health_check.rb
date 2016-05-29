class Fluent::HTTPOutput < Fluent::Output
  Fluent::Plugin.register_output('health_check', self)

  def initialize
    super
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
      tmpfile = record["file"]
      nonce = record["nonce"]
      puts "tmpfile" + tmpfile
      open("/tmp/" + tmpfile, 'w') { |f|
        f.puts nonce
      }
    rescue
      puts $!
    end
  end

  def emit(tag, es, chain)
    es.each do |time, record|
      handle_record(tag, time, record)
    end
    chain.next
  end
end