require 'securerandom'
require 'nokogiri'
require 'tmpdir'

module VRO

  # Represents a vRO package element
  class Element
    attr_reader :name
    attr_reader :type

    def initialize(path)
      @name = File.basename(path)
      @dirname = File.dirname(path)
      @type = nil
      print "Initializing element: %s\n" % name
    end

    def path
      "%s/%s" % [@dirname,@name]
    end

    # Only relocate these element types
    def relocatable?
      ['Workflow','ScriptModule'].include? @type
    end

    # Given a map: stale references -> new references
    #  update linked-workflow-id's in data
    def update_references(stale_refs)
      doc = nil
      # Read data file as xml
      File.open("%s/data" % path) do |data|
        doc = Nokogiri::XML(data.read)
      end

      # Find and replace link references
      element_links = doc.xpath("//xmlns:workflow-item[@type='link']")
      element_links.each do |link|
        ref_id = link["linked-workflow-id"]
        if stale_refs.include? ref_id
          link["linked-workflow-id"] = stale_refs[ref_id]
          print "Mapped %s to %s\n" % [ref_id, stale_refs[ref_id]]
        else
          print "Oddity: Unknown linked-workflow-id: %s\n" % ref_id
        end
      end

      # Update/overwrite data file
      outf = File.open("%s/data" % path, 'w')
      outf.write(doc.to_xml)
      outf.close
      print "Updated References for element: %s\n" % [name]
    end

    def relocate_scriptmodule(category,doc)
      el_cat = doc.xpath("//category")
      if el_cat.size != 1
        print "Error: Found %d category elements in %s\n" % [el_cat.size,name]
        return
      end
      el_cat = el_cat[0]
      ns = el_cat["name"]
      new_ns = "%s.%s" % [category,ns]
      el_cat["name"] = new_ns
      el_name = el_cat.child
      el_cdat = Nokogiri::XML::CDATA.new(doc, new_ns)
      el_name.children = el_cdat
    end

    def relocate_workflow(category, doc)
      el_cats = doc.xpath("//categories")[0]

      el_cat = Nokogiri::XML::Node.new("category", doc)
      el_cat["name"] = category
      el_name = Nokogiri::XML::Node.new("name", doc)
      el_cdat = Nokogiri::XML::CDATA.new(doc, category)
      el_name.add_child el_cdat
      el_cat.add_child el_name

      # Prepend this category in front of existing ones if present
      el_top = el_cats.first_element_child
      if el_top
        el_top.add_previous_sibling(el_cat)
      else
        el_cats.add_child(el_cat)
      end
    end

    # Relocate the path location of this element in vRO
    def relocate(category)
      doc = nil
      File.open("%s/categories" % path) do |cats|
        doc = Nokogiri::XML(cats.read)
      end

      if type == 'Workflow'
        relocate_workflow(category,doc)
      end
      if type == 'ScriptModule'
        relocate_scriptmodule(category,doc)
      end

      outf = File.open("%s/categories" % path, 'w')
      noformat_nodecl = Nokogiri::XML::Node::SaveOptions::NO_DECLARATION

      outf.write(doc.to_xml(save_with:noformat_nodecl))
      outf.close
      print "Relocated %s %s to %s\n" % [type, name, category]
    end

    def rename(name)
      doc = nil
      File.open("%s/info" % path) do |info|
        doc = Nokogiri::XML(info.read)
      end
      # Get the type
      element_type = doc.xpath("//entry[@key='type']")[0].content
      @type = element_type

      unless relocatable?
        print "Skipping element %s of type %s\n" % [name, type]
        return
      end

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

  # Represents a vRO package
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

    def update_references(stale_refs)
      @elements.select{|e| e.type == "Workflow"}.each do |wf|
        wf.update_references(stale_refs)
      end
    end

    def fork(name, category_name)
      # Instead of creating a new package
      # try modifying this one.
      stale_refs = {}
      @elements.each do |el|
        guid = SecureRandom.uuid

        # Only relocatable elements are renamed by Element::rename
        el.rename(guid)

        # Relocate workflows and actions
        if el.relocatable?
          el.relocate(category_name)

          # Store old refs and new name
          stale_refs[el.name] = guid
        end
      end

      # Remap workflow references
      update_references(stale_refs)

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