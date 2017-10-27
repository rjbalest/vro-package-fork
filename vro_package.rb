require 'securerandom'
require 'nokogiri'
require 'tmpdir'

module VRO

  class Element
    attr_reader :name
    def initialize(path)
      @name = File.basename(path)
      @dirname = File.dirname(path)
      @type = nil
      print "Initializing element: %s\n" % name
    end

    def path
      "%s/%s" % [@dirname,@name]
    end

    def relocatable?
      ['Workflow','Action'].include? @type
    end

    # Relocate the path location of this element in vRO
    def relocate(category)
      doc = nil
      File.open("%s/categories" % path) do |cats|
        doc = Nokogiri::XML(cats.read)
      end

      el_cats = doc.xpath("//categories")[0]

      el_cat = Nokogiri::XML::Node.new "category", doc
      el_cat["name"] = category
      el_name = Nokogiri::XML::Node.new "name", doc
      el_cdat = Nokogiri::XML::CDATA.new doc, category
      el_name.add_child el_cdat
      el_cat.add_child el_name

      # Prepend this category in front of existing ones if present
      el_top = el_cats.first_element_child
      if el_top
        el_top.add_previous_sibling(el_cat)
      else
        el_cats.add_child(el_cat)
      end

      outf = File.open("%s/categories" % path, 'w')
      noformat_nodecl = Nokogiri::XML::Node::SaveOptions::NO_DECLARATION

      outf.write(doc.to_xml(save_with:noformat_nodecl))
      outf.close
      print "Relocated %s to %s\n" % [name, category]
    end

    def rename(name)
      doc = nil
      File.open("%s/info" % path) do |info|
        doc = Nokogiri::XML(info.read)
      end
      # Get the type
      element_type = doc.xpath("//entry[@key='type']")[0].content
      @type = element_type

      doc.xpath("//entry[@key='id']")[0].content=name

      newpath = "%s/%s" % [@dirname,name]
      File.rename(path, newpath)

      outf = File.open("%s/info" % newpath, 'w')
      outf.write(doc.to_xml)
      outf.close
      print "Moved element %s to %s\n" % [@name,name]
      @name = name
    end

  end

  class Package

    attr_accessor :name
    attr_accessor :elements

    def initialize(path)
      @path = path
      packagefile = File.basename(@path)
      @name = packagefile.split(".package")[0]
      @elements = []

      @cpath = Dir.mktmpdir
      explode
      import_elements
      print "Exploded package into %s\n" % @cpath
    end

    def import_elements
      Dir["%s/elements/*" % @cpath].select{ |f| File.directory? f }.each do |path|
        el = Element.new(path)
        @elements << el
      end

    end

    def explode
      tarcmd = "tar xfC %s %s" % [@path, @cpath]
      %x[#{tarcmd}]
    end

    def archive
      tarcmd = "tar cfC %s.package %s certificates elements signatures dunes-meta-inf" % [@name, @cpath]
      %x[#{tarcmd}]
      print "Forked package to %s.package\n" % @name
    end

    def fork(name, category_name)
      # Instead of creating a new package
      # try modifying this one.
      stale_refs = {}
      @elements.each do |el|
        guid = SecureRandom.uuid

        # Store old refs and new name
        stale_refs[el.name] = guid
        el.rename(guid)

        # Relocate workflows and actions
        if el.relocatable?
          el.relocate(category_name)
        end
      end

      # Rename this package
      @name = name

      # Rearchive it
      archive
    end

    def read_info(path)
      data = File.open(path).read
      doc = Nokogiri::XML(data)
      doc.xpath("//entry[@key='id']")[0].content="foo"
    end

  end
end