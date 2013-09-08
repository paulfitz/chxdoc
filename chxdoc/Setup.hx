package chxdoc;

import haxe.xml.Fast;
import sys.io.File;
import sys.FileSystem;
import chxdoc.FilterPolicy;

using StringTools;

class Setup {
	/** Xml config **/
	static var xmlconfig : Fast;
	/** cache of settings, to prevent constant xml searching **/
	static var cache : Map<String, String>;

	/// testing only ///
	static function main() {
		initialize();
		setup();
		trace(prettyPrint(xmlconfig,0));
		trace(ChxDocMain.config);
		
	}

	/////////////////////////////////////////////////////////////////////
	///////////////////////// Public API ////////////////////////////////
	/////////////////////////////////////////////////////////////////////
	
	public static function setup() {
		var c = ChxDocMain.config;

		initialize();

		// this whole block does not apply to neko.Web
		#if neko
		if(!neko.Web.isModNeko) {
		#end

		// check if verbose is on command line
		for( a in Sys.args() ) {
			if( a == "-v")
				c.verbose = true;
		}
		
		// if the user does not have an existing ~/.chxdoc
		// attempt to create it.
		var home = Utils.getHomeDir();
		try {
			if(home == null) {
				ChxDocMain.logWarning("Unable to determine home path");
			}
			else if(!FileSystem.exists(home + ".chxdoc")) {
				Sys.println("Creating default " + home + ".chxdoc");
				writeConfig(home + ".chxdoc", true);
			}
		} catch(e:Dynamic) {
			ChxDocMain.fatal("Unable to create " + home + ".chxdoc");
		}

		// erase any list entries created by initialize()
		setListVal("files",[],true);
		setListVal("filters",[],true);
		
		// load user's home/.chxdoc
		try {
			if(home != null)
				loadConfigFile(home + ".chxdoc");
		} catch(e:Dynamic) {
			ChxDocMain.fatal("Error reading " + home + ".chxdoc : "+Std.string(e));
		}

		// end of neko.Web.isModNeko test
		#if neko
		}
		#end
	}

	/**
	 * Load a chxdoc config xml file
	 * @param filename File name
	 **/
	public static function loadConfigFile(filename:String) {
		populate(load(filename));
	}

	/**
	 * Write current configuration to a file.
	 * @param filename File to write to
	 * @param commentLists Comment out entries in lists like <files> and <filters>
	 **/
	public static function writeConfig(filename:String, commentLists:Bool=false) {
		try {
			var fo = File.write(filename, false);
			fo.writeString( prettyPrint(xmlconfig,0,commentLists) );
			fo.close();
		} catch(e:Dynamic) {
			ChxDocMain.fatal("Error writing " + filename + ": " + Std.string(e));
		}
	}

	/**
	 * Delete a config node
	 *
	 * @param name Element name
	 **/
	public static function deleteVal(name:String) {
		var n = findNode(name);
		if(n == null)
			return;
		xmlconfig.x.removeChild(n.x);
	}
	
	/**
	 * Write a val to the xml config
	 * @param name Xml node name
	 * @param val Value to place in 'value' attribute.
	 **/
	public static function writeVal(name:String, val:Dynamic) {
		var n = findNode(name);
		if(n == null) {
			var e = Xml.createElement(name);
			e.set("value", escape(val));
			xmlconfig.x.addChild(e);
			return;
		}
		n.x.set( "value", val );
	}

	/**
	 * Adds to the filters.
	 **/
	public static function addFilter(path:String, policy:FilterPolicy) {
		var n = findOrCreateNode("filters");
		n.x.addChild(createFilterEntry(path, policy));
		switch(policy) {
			case ALLOW:
				Filters.allow(path);
			case DENY:
				Filters.deny(path);
		}
	}

	public static function setFilterPolicy(policy:FilterPolicy) {
		var n = findOrCreateNode("filters");
		n.x.set("policy", (policy == ALLOW) ? "allow" : "deny");
		Filters.setDefaultPolicy(policy);
	}

	/**
	 * Adds a doc target specified by --file or -f. Checks if an entry for
	 * the filename exists already and will update existing entries
	 *
	 * @param filename Name of the xml file generated by haxe
	 * @param platform Target platform name or null
	 * @param remap Remap target or null
	 **/
	public static function addTarget(filename:String, platform:String, remap:String) {
		var n = findOrCreateNode("files");
		for(i in n.nodes.file) {
			if(i.name == filename) {
				n.x.removeChild(i.x);
			}
		}
		var found = false;
		for(e in ChxDocMain.config.files) {
			if(e.name == filename) {
				e.platform = platform;
				e.remap = remap;
				found = true;
				break;
			}
		}
		if(!found)
			ChxDocMain.config.files.push({name:filename, platform:platform, remap:remap});
		n.x.addChild(createFileEntry(filename, platform, remap));
	}

	// Setup.writeVal("", config.);



	
	/////////////////////////////////////////////////////////////////////
	///////////////////////// Private ///////////////////////////////////
	/////////////////////////////////////////////////////////////////////
	/**
	 * Load xmlconfig from a file
	 * @return Xml data
	 * @throws Strings on errors
	 **/
	static function load(path:String) : Fast {
		if(!FileSystem.exists (path))
			throw "'"+path+"' does not exist";
		var xml:Fast = null;
		try {
			xml = new Fast(Xml.parse(File.getContent(path)).firstElement());
		} catch (e:Dynamic) {
			throw(path + " is not valid XML");
			return null;
		}
		return xml;
	}

	/**
	 * Populate xmlconfig from xml
	 * @param xml Xml data
	 **/
	static function populate(xml:Fast) {
		for(n in xml.elements) {
			var name = n.name;
			var value = n.has.value ? n.att.value : null;

			if(name == "files") {
				for( f in n.nodes.file ) {
					if(!f.has.name)
						throw "<file> node has no 'name' attribute";
					name = f.att.name;
					var platform = f.has.platform ? f.att.platform : null;
					var remap = f.has.remap ? f.att.remap : null;
					setListVal("files",[createFileEntry(name,platform,remap)],false);
				}
			}
			else if(name == "filters") {
				for( f in n.nodes.filter ) {
					if(!f.has.path)
						throw "<filter> node has no 'path' attribute";
					if(!f.has.policy)
						throw "<filter> node has no 'policy' attribute";
					var p = ALLOW;
					switch(f.att.policy) {
						case "allow": p = ALLOW;
						case "deny" : p = DENY;
						default : throw "<filter> policy '"+f.att.policy+"' is invalid";
					}
					setListVal("filters",[createFilterEntry(f.att.path, p)],false);
				}
			} else {
				if(value == null)
					throw "No 'value' attribute for "+name;
				setVal(name, value);
			}
		}
	}
	
	/**
	 * Creates xmlconfig using default values
	 **/
	static function initialize() {
		cache = new Map();
		xmlconfig = new Fast(Xml.parse("<xml></xml>").firstElement());
		setVal("title", "Haxe Application");
		setVal("subtitle", "<a href='http://www.haxe.org/' target='new'>http://www.haxe.org/</a>");
		//setListVal("platforms",
		setVal("headerText","");
		setVal("footerText","");

		setVal("headerTextFile","");
		setVal("footerTextFile", "");

		setListVal("files",[
				createFileEntry("flash9.xml","flash","flash9"),
				createFileEntry("neko.xml","neko")
			]);

		setVal("dateShort", "%Y-%m-%d");
		setVal("dateLong", "%a %b %d %H:%M:%S %Z %Y");

		setVal("developer", false);
		setVal("showAuthorTags", false);
		setVal("showMeta",true);
		setVal("showPrivateClasses", false);
		setVal("showPrivateTypedefs", false);
		setVal("showPrivateEnums", false);
		setVal("showPrivateMethods", false);
		setVal("showPrivateVars", false);
		setVal("showTodoTags", false);

		setVal("output","./docs/");
		//setVal("packageDirectory","./docs/packages/"); // not user configurable
		//setVal("typeDirectory","./docs/types/");

		setListVal("filters",[
				createFilterEntry("haxe.io.Bytes", DENY),
				createFilterEntry("sys.db.*", ALLOW)
			], true, { policy : "allow" });
		
		setVal("template","default");
		setVal("templatesDir","");
		var c = ChxDocMain.config;
		// Set template to haxelib chxdoc default template
		// if possible.
		var tpl : String = null;
		try {
			var p = new sys.io.Process("haxelib",["path", "chxdoc"]);
			var dir = p.stdout.readLine();
			tpl = dir + "/templates/";
			if(FileSystem.isDirectory(tpl)) {
				if(FileSystem.isDirectory(tpl + "default")) {
					setVal("templatesDir", tpl);
					setVal("template", "default");
				}
			}
		} catch(e:Dynamic) {
			ChxDocMain.logWarning("Could not find chxdoc in haxelib ("+tpl+")");
		}
		setVal("macros","macros.mtt");
		
		setVal("htmlFileExtension","html");
		setVal("stylesheet","stylesheet.css");

		setVal("mergeMeta", true);

		//setVal("noPrompt", false);
		setVal("installImagesDir","true");
		setVal("installCssFile","true");

		setVal("generateTodo", false);
		//setListVal("todoLines",[""]);
		//setVal("todoFile","todo.html"); not user configurable

		setVal("verbose", false);
		setVal("tmpDir","./__chxdoctmp/");
		
		//setVal("xmlBasePath",""); // in <files>
		setVal("webPassword","");
	}

	static function escape(val:Dynamic) {
		var s = Std.string(val);
		return s.replace('"', "\\\"");
	}

	/**
	 * Find an element node in the xmlconfig by name
	 **/
	static function findNode(name:String) : Fast {
		if(xmlconfig.hasNode.resolve(name))
			return xmlconfig.node.resolve(name);
		return null;
	}

	/**
	 * Will try to find node 'name' but will create it if not found.
	 * @param name Element name
	 **/
	static function findOrCreateNode(name:String) : Fast {
		var n = findNode(name);
		if(n == null) {
			n = new Fast(Xml.createElement(name));
			xmlconfig.x.addChild(n.x);
		}
		return n;
	}

	/**
	 * Create an entry to go under <files>
	 * 
	 * @param file Xml file name
	 * @param platform Haxe output target platform
	 * @param remap Platform to remap to
	 **/
	static function createFileEntry(file:String, platform:String=null, remap:String=null) : Xml {
		var n = Xml.createElement("file");
		n.set("name", file);
		if(platform != null)
			n.set("platform", platform);
		if(remap != null)
			n.set("remap",remap);
		return n;
	}

	/**
	 * Create an entry to go under <filters>
	 *
	 * @param pkgOrClass Globbed pkg or specific class path
	 **/
	static function createFilterEntry(pkgOrClass:String, policy:FilterPolicy) : Xml {
		var n = Xml.createElement("filter");
		n.set("path", pkgOrClass);
		n.set("policy", ((policy == ALLOW) ? "allow" : "deny"));
		return n;
	}

	/**
	 * Search for or create a node, and assign 'val' to the
	 * value attribute, and pass the value through the command
	 * line parameter parsing in ChxDocMain
	 *
	 * @param name Xml node name
	 * @param val Value to place in 'value' attribute.
	 **/
	static function setVal(name:String, val:Dynamic) {
		writeVal(name, val);
		try {
			ChxDocMain.handleArg("--"+name, function(errMsg) { return Std.string(val); }, true);
		} catch(e:String) {
			throw "Unknown element <" + name + ">";
		}
	}



	/**
	 * Populate an element with an array of xml values as children and
	 * passes the value through the command line parsing in ChxDocMain
	 * 
	 * @param name Name of the parent node to find or create
	 * @param values Array of Xml children to add
	 * @param remove Clears existing children from node 'name'
	 * @throws String on format errors in 'values' array
	 **/
	static function setListVal(name:String, values:Array<Xml>,remove:Bool=true, atts:Dynamic=null) {
		var n = findOrCreateNode(name);
		if(atts != null)
			for(f in Reflect.fields(atts))
				n.x.set(f, Std.string(Reflect.field(atts, f)));

		if(remove) {
			var ea : Array<Xml> = [];
			// populate a list of existing elements
			for(e in n.elements)
				ea.push(e.x);
			// then remove them.
			for(e in ea)
				n.x.removeChild(e);
			if(name == "files")
				ChxDocMain.config.files = new Array();
			else if(name == "filters")
				Filters.clear();
		}
		for(v in values) {
			if(name == "files") {
				if(!v.exists("name"))
					throw "<file> entry requires name attribute";
				var p = v.get("name");
				if(v.exists("platform")) {
					p += "," + v.get("platform");
					if(v.exists("remap"))
						p += "," + v.get("remap");
				}
				ChxDocMain.handleArg("--file", function(s) { return p; }, true);
			} else if(name == "filters") {
				if(!v.exists("path"))
					throw "<filter> entry requires path attribute";
				if(!v.exists("policy"))
					throw "<filter> entry requires policy attribute";
				var policy = v.get("policy").toLowerCase();
				if(policy == "allow")
					ChxDocMain.handleArg("--allow", function(s) return v.get("path"), true);
				else if(policy == "deny")
					ChxDocMain.handleArg("--deny", function(s) return v.get("path"), true);
				else
					throw "<filter> policy '"+v.get("policy")+"' is invalid";
			} else {
				throw "Unexpected list " + name;
				//n.x.addChild(v);
			}
		}
		return n;
	}

	/////////////////////////////////////////////////////////////////////
	//////////// Value getters for non-list elements ////////////////////
	/////////////////////////////////////////////////////////////////////
	static function getStringVal(name:String, defaultVal:String=null) {
		var n = findNode(name);
		if(n == null)
			return defaultVal;
		try {
			var val = n.att.resolve(name);
			return val;
		} catch(e:Dynamic) {}
		return defaultVal;
	}
	
	static function getBoolVal(name:String, defaultVal:Null<Bool>) {
		var dvs : String = if(defaultVal ==null) null else defaultVal ? "true" : "false";
		var val = getStringVal(name, dvs);
		if(val == null)
			return null;
		val = val.toLowerCase();
		var c = val.charAt(0);
		if(c == 'y' || c == 't')
			return true;
		return false;
	}

	static function getIntVal(name:String, defaultVal:Null<Int>) : Null<Int> {
		var val = null;
		if(defaultVal == null)
			val = getStringVal(name, null);
		else
			getStringVal(name, Std.string(defaultVal));
		if(val == null)
			return null;
		var n = Std.parseInt(val);
		if(val == null)
			return defaultVal;
		return n;
	}

	static function prettyPrint(xml:Fast, lvl:Int=0, commentLists:Bool=false) : String {
		var s : String = "";
		if(lvl == 0) {
			s = "<xml>\n";
			s += prettyPrint(xml, 1, commentLists);
			s += "</xml>\n";
			return s;
		}
		var indent = "";
		for(i in 0...lvl)
			indent += "  ";
		
		for(e in xml.elements) {
			var hasChildren = false;
			var comment = commentFor(e.name);
			if(comment != null) {
				s += "\n" + indent;
				s += Std.string(comment) + "\n";
			}
			s += indent;
			s += "<";
			s += e.name;
			var alist = e.x.attributes();
			var clist = e.x.iterator();
			if(clist.hasNext() || e.name=="files") {
				hasChildren = true;
			}
			for(a in alist) {
				s += " ";
				s += (a + "=" + '"');
				s += e.x.get(a);
				s += '"';
			}
			if(hasChildren) {
				s += ">\n";
				if(commentLists /*&& (e.name == "files" || ...)*/)
					s += indent + "<!--\n";
				s += prettyPrint(e, lvl + 1, false);
				if(commentLists /*&& (e.name == "files" || ...)*/)
					s += indent + "-->\n";
				s += indent + "</" + e.x.nodeName + ">\n";
			} else {
				s += " />\n";
			}
		}
		return s;
	}

	static function commentFor(name:String) : Xml {
		var mkc = Xml.createComment;
		return switch(name) {
			case "verbose": mkc("Turn on verbose mode");
			case "dateShort":
				mkc("Format for dates");
			case "showAuthorTags":
				mkc("Show @author values in docs");
			case "showPrivateClasses":
				mkc("Output items marked private");
			case "developer":
				mkc("Turns on all show* values, regardless of their value. Should come before any show* entries");
			case "generateTodo":
				mkc("Turn on todo generation. and file to output todo list to");
			case "htmlFileExtension":
				mkc("File extension for html documentation files");
			case "title":
				mkc("Title, subtitle, headers and footers on pages");
			case "installImagesDir":
				mkc("Copy the images or css from template to output directory");
			case "template":
				mkc("Template name, templates base directory and macros file name of main macros");
			case "output":
				mkc("Output directory");
			case "stylesheet":
				mkc("The stylesheet to use");
			case "webPassword":
				mkc("Password for mod_neko integration");
			case "files":
				mkc("Xml files to parse. List of <file name=\"\" platform=\"\" [remap=\"\"]>");
			case "tmpDir":
				mkc("Temporary directory name for template compilation");
			case "headerTextFile":
				mkc("Files to read in as header or footer text");
			case "filters":
				mkc("Excluded packages or classes in <exclude value='my.pkg.*'> elements");
			case "mergeMeta":
				mkc("Merge metadata with same names as @doc tags with the @doc tags");
			default: null;
		}
	}
}
