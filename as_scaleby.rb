=begin

Copyright 2020-2020, Alexander C. Schreyer
All rights reserved

THIS SOFTWARE IS PROVIDED "AS IS" AND WITHOUT ANY EXPRESS OR IMPLIED WARRANTIES,
INCLUDING, WITHOUT LIMITATION, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND
FITNESS FOR A PARTICULAR PURPOSE.

License:        GPL (http://www.gnu.org/licenses/gpl.html)

Author :        Alexander Schreyer, www.alexschreyer.net, mail@alexschreyer.net

Website:        https://alexschreyer.net/projects/scale-by-image-equation-tools-extension-for-sketchup/

Name :          Scale By Tools

Version:        1.0

Date :          7/2/2020

Description :   A set of tools to scale/move/rotate several objects/faces/vertices based on an image or a mathematical formula (power or sine/cosine).
                
                This extension combines several of my scripts from my book and sketchupfordesign.com.

Usage :         Tools > Scale By Tools
                or Scale By Tools toolbar

History:        1.0 (7/2/2020):
                - Initial release
                1.1 (TBD):
                - Added warning for pre-2018 users
                - Added missing toolbar icons (mac, old)
                
ToDo:           - Could add phase shift for sine and remove cosine

=end


# ========================


require 'sketchup.rb'
require 'extensions.rb'


# ========================


module AS_Extensions

  module AS_ScaleBy
  
    @extversion           = "1.0"
    @exttitle             = "Scale By Tools"
    @extname              = "as_scaleby"
    
    @extdir = File.dirname(__FILE__)
    @extdir.force_encoding('UTF-8') if @extdir.respond_to?(:force_encoding)
    
    loader = File.join( @extdir , @extname , "as_scaleby.rb" )
   
    extension             = SketchupExtension.new( @exttitle , loader )
    extension.copyright   = "Copyright 2020-#{Time.now.year} Alexander C. Schreyer"
    extension.creator     = "Alexander C. Schreyer, www.alexschreyer.net"
    extension.version     = @extversion
    extension.description = "A set of tools to scale/move/rotate several objects/faces/vertices based on an image or a mathematical formula (power or sine/cosine)."
    
    Sketchup.register_extension( extension , true )
         
  end  # module AS_ScaleBy
  
end  # module AS_Extensions


# ========================
