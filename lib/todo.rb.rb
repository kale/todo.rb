
COLORIZER = File.join(File.dirname(__FILE__), 'colorizer.rb')
HTML = File.join(File.dirname(__FILE__), 'html.rb')

class TodoRb

  attr_accessor :todo_file, :done_file, :backup_file, :formatter

  def initialize(opts={})

    defaults = { 
      todo_file: 'todo.txt',
      done_file: 'done.txt'
    }
    @opts = defaults.merge opts
    @formatter = {
      color: COLORIZER,
      nocolor: "#{COLORIZER} --no-color",
      html: HTML
    }[@opts[:formatter]]

    @todo_file = @opts[:todo_file]
    @backup_file = ".#{@todo_file}.bkp"
    @done_file = @opts[:done_file]
    make_files
  end

  def make_files
    [todo_file, done_file].each do |f|
      if !File.exist?(f)
        $stderr.puts "Missing a #{f} file. Creating."
        `touch #{f}`
      end
    end
  end

  def backup
    `cp #{todo_file} #{backup_file}`
  end

  def ed_command! command, *input_text
    backup
    text = input_text.empty? ? nil : "\n#{input_text.join(' ')}\n."
    IO.popen("ed -s #{todo_file}", 'w') {|pipe|
      script = <<END
#{command}#{text}
wq
END
      pipe.puts script
      pipe.close
    }
    exec "diff #{backup_file} #{todo_file}"
  end

  def revert
    return unless File.exist?(backup_file)
    exec <<END
mv #{todo_file} #{backup_file}.2
mv #{backup_file} #{todo_file}
mv #{backup_file}.2 #{backup_file}
END
  end

  def diff
    return unless File.exist?(backup_file)
    exec "diff #{backup_file} #{todo_file}"
  end

  def filter(opts={})
    defaults = {list_file: todo_file, no_exec: false}
    if opts[:list]
      opts[:list_file] = opts[:list] == :todo ? todo_file : done_file
    end
    opts = defaults.merge opts
    tag = opts[:tag]

    # note don't put /< before the grep arg
    grep_filter = tag ? " | grep -i '#{tag}\\>' " : ""
    script = <<END
cat -n #{opts[:list_file]} #{grep_filter} | #{formatter} #{tag ? "'#{tag}'" : ''}
END
    if opts[:no_exec] # just return for further processing
      script
    else
      exec(script)
    end
  end

  def list_all tag=nil
    a = filter tag:tag, list_file:todo_file, no_exec:true
    b = filter tag:tag, list_file:done_file, no_exec:true
    exec ["echo 'todo'", a, "echo 'done'", b].join("\n")
  end

  def mark_done! range
    return unless range =~ /\S/
    backup
    exec <<END
cat #{todo_file} | sed -n '#{range}p' | 
  awk '{print d " " $0}' "d=$(date +'%Y-%m-%d')" >> #{done_file}
echo "#{range}d\nwq\n" | ed -s #{todo_file} 
diff #{backup_file} #{todo_file}
END
  end

  def mark_undone! range
    return unless range =~ /\S/
    backup
    exec <<END
cat #{done_file} | sed -n '#{range}p' | 
  ruby -n -e  'puts $_.split(" ", 2)[1]'  >> #{todo_file}
echo "#{range}d\nwq\n" | ed -s #{done_file} 
diff #{backup_file} #{todo_file}
END
  end


  def external_edit(range)
    require 'tempfile'
    f = Tempfile.new('todo.rb')
    `sed -n '#{range}p' #{todo_file} > #{f.path}`
    system("#{ENV['EDITOR']}  #{f.path}")
    new_text = File.read(f.path).strip
    range.inspect
    if range != ""
      ed_command! "#{range}c", new_text
    else
      `cp #{f.path} #{todo_file}`
    end
  end

  TAG_REGEX = /[@\+]\S+/
   
  def report
    report_data = get_report_data 
    # count priority items per tag
    File.readlines(todo_file).inject(report_data) {|report_data, line|
      line.scan(TAG_REGEX).each {|tag|
        report_data[tag][:priority] ||= 0
        if line =~ /!/
          report_data[tag][:priority] = report_data[tag][:priority] + 1
        end
      }; report_data
    }
    longest_tag_len = report_data.keys.reduce(0) {|max, key| [max, key.length].max} + 1
    placeholders = "%#{longest_tag_len}s %5s %5s %5s" 
    headers = %w(tag pri todo done)
    IO.popen(formatter, 'w') {|pipe|
      pipe.puts(placeholders % headers)
      pipe.puts placeholders.scan(/\d+/).map {|a|'-'*(a.to_i)}.join(' ')
      report_data.keys.sort_by {|k| k.downcase}.each {|k|
        pipe.puts placeholders % [k, report_data[k][:priority], report_data[k][:todo], report_data[k][:done]].map {|x| x == 0 ? ' ' : x}
      }
    }
  end

  def get_report_data 
    [:todo, :done].
      select {|a| File.exist?(send("#{a}_file"))}.
      inject({}) {|m, list|
        file = "#{list}_file"
        File.read(send(file)).scan(TAG_REGEX).group_by {|t| t}.
          map {|k, v|
            m[k] ||= {todo:0,done:0,priority:0}
            m[k][list] = (m[k][list] || 0) + v.size
          }
        m
      }
  end

  def self.expand_tag(t)
    return unless t
    re = /^#{Regexp.escape(t)}/
    match = new.get_report_data.keys.detect {|key| key =~ re} 
    if match && match != t
      match
    else
      t
    end
  end
end


