require 'puppet/util/autoload'
require 'puppet/parser/scope'
require 'monitor'

# A module for managing parser functions.  Each specified function
# is added to a central module that then gets included into the Scope
# class.
module Puppet::Parser::Functions
  Environment = Puppet::Node::Environment

  class << self
    include Puppet::Util
  end

  # This is used by tests
  def self.reset
    @functions = Hash.new { |h,k| h[k] = {} }.extend(MonitorMixin)
    @modules = Hash.new.extend(MonitorMixin)

    # Runs a newfunction to create a function for each of the log levels
    Puppet::Util::Log.levels.each do |level|
      newfunction(level, :doc => "Log a message on the server at level #{level.to_s}.") do |vals|
        send(level, vals.join(" "))
      end
    end
  end

  def self.autoloader
    @autoloader ||= Puppet::Util::Autoload.new(
      self, "puppet/parser/functions", :wrap => false
    )
  end

  def self.environment_module(env = nil)
    if env and ! env.is_a?(Puppet::Node::Environment)
      env = Puppet::Node::Environment.new(env)
    end
    @modules.synchronize {
      @modules[ (env || Environment.current || Environment.root).name ] ||= Module.new
    }
  end

  # Create a new function type.
  def self.newfunction(name, options = {}, &block)
    name = name.intern

    Puppet.warning "Overwriting previous definition for function #{name}" if functions.include?(name)

    ftype = options[:type] || :statement

    unless ftype == :statement or ftype == :rvalue
      raise Puppet::DevError, "Invalid statement type #{ftype.inspect}"
    end

    fname = "function_#{name}"
    environment_module.send(:define_method, fname, &block)

    # Someday we'll support specifying an arity, but for now, nope
    #functions[name] = {:arity => arity, :type => ftype}
    functions[name] = {:type => ftype, :name => fname}
    functions[name][:doc] = options[:doc] if options[:doc]
  end

  # Remove a function added by newfunction
  def self.rmfunction(name)
    name = name.intern

    raise Puppet::DevError, "Function #{name} is not defined" unless functions.include? name

    functions.delete name

    fname = "function_#{name}"
    environment_module.send(:remove_method, fname)
  end

  # Determine if a given name is a function
  def self.function(name)
    name = name.intern

    @functions.synchronize do
      unless functions.include?(name) or functions(Puppet::Node::Environment.root).include?(name)
        autoloader.load(name,Environment.current || Environment.root)
      end
    end

    ( functions(Environment.root)[name] || functions[name] || {:name => false} )[:name]
  end

  def self.functiondocs
    autoloader.loadall

    ret = ""

    functions.sort { |a,b| a[0].to_s <=> b[0].to_s }.each do |name, hash|
      ret += "#{name}\n#{"-" * name.to_s.length}\n"
      if hash[:doc]
        ret += Puppet::Util::Docs.scrub(hash[:doc])
      else
        ret += "Undocumented.\n"
      end

      ret += "\n\n- *Type*: #{hash[:type]}\n\n"
    end

    ret
  end

  def self.functions(env = nil)
    @functions.synchronize {
      @functions[ env || Environment.current || Environment.root ]
    }
  end

  # Determine if a given function returns a value or not.
  def self.rvalue?(name)
    (functions[name.intern] || {})[:type] == :rvalue
  end

  reset  # initialize the class instance variables
end
