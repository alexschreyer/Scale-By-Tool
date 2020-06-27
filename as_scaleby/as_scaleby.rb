# ==================
# Main file for ScaleBy
# by Alex Schreyer
# ==================


require 'sketchup.rb'


# ==================


module AS_Extensions

  module AS_ScaleBy
  
  
    # ==================
    
    
    # Helper function to convert a SketchUp color to greyscale (0..1)
    def self.grey( color )
      g = color.red.to_f / 255 * 0.2126 + 
          color.green.to_f / 255 * 0.7152 + 
          color.blue.to_f / 255 * 0.0722
      return g
    end  
    
    
    # ==================
    
    
    def self.scale_by_image
    # Scale objects based on image grayscale
    
        mod = Sketchup.active_model
        ent = mod.entities
        sel = mod.selection
        
        toolname = "Scale Objects by Image"      
        
        # Get all objects from selection
        all_objects = []
        all_objects.push( *sel.grep( Sketchup::ComponentInstance ) )
        all_objects.push( *sel.grep( Sketchup::Group ) )
        
        if !all_objects.empty?
        
            # Get all the parameters from input dialog
            prompts = [ "MAX Scale Variation RED (x, 0 = none) " , 
                        "MAX Scale Variation GREEN (y, 0 = none) " , 
                        "MAX Scale Variation BLUE (z, 0 = none) " ,
                        "MAX Rotation Variation (degrees) " ,
                        "Image Orientation " ]
            defaults = [ "0" , "0" , "1" , "0" , "RED-GREEN (x-y)" ]
            lists = [ "" , "" , "" , "" , "RED-GREEN (x-y)|RED-BLUE (x-z)|GREEN-BLUE (y-z)" ]
            res = UI.inputbox( prompts , defaults , lists , toolname )
            return if !res
            
            mod.start_operation toolname
            
            begin
            
                x_var = res[0].to_f
                y_var = res[1].to_f
                z_var = res[2].to_f
                rot_var = res[3].to_i

                # Ask for an image file
                f = UI.openpanel 'Select an image file', '', 'Image Files|*.jpg;*.png;||'
                return if f == nil

                # Now load the image
                ir = Sketchup::ImageRep.new
                ir.load_file( f )

                # Create temporary group from selection to get dimensions
                gr = ent.add_group( all_objects )
                min = gr.bounds.min
                max = gr.bounds.max

                # Work with entities in group
                gr.entities.each_with_index { |e,i|
                
                    # Get center of object
                    if e.is_a? Sketchup::ComponentInstance
                        cen = e.transformation.origin
                    else
                        cen = e.bounds.center
                    end
                    
                    # Scale based on orientation
                    if res[4] == "RED-BLUE (x-z)"  # Front orientation
                    
                        width = ( max - min ).x.to_f
                        height = ( max - min ).z.to_f

                        x = cen.x.to_f / width * ir.width
                        z = cen.z.to_f / height * ir.height

                        scale = self.grey( ir.color_at_uv( x / ir.width , z / ir.height, true) )     
                        
                        t_rot = Geom::Transformation.rotation cen , mod.axes.yaxis , ( scale * rot_var ).degrees
                    
                    elsif res[4] == "GREEN-BLUE (y-z)"  # Side orientation
                    
                        width = ( max - min ).y.to_f
                        height = ( max - min ).z.to_f

                        y = cen.y.to_f / width * ir.width
                        z = cen.z.to_f / height * ir.height

                        scale = self.grey( ir.color_at_uv( y / ir.width , z / ir.height, true) )      
                        
                        t_rot = Geom::Transformation.rotation cen , mod.axes.xaxis , ( scale * rot_var ).degrees
                    
                    else  # Flat on the ground
                    
                        width = ( max - min ).x.to_f
                        height = ( max - min ).y.to_f

                        x = cen.x.to_f / width * ir.width
                        y = cen.y.to_f / height * ir.height

                        scale = self.grey( ir.color_at_uv( x / ir.width , y / ir.height, true) )     
                        
                        t_rot = Geom::Transformation.rotation cen , mod.axes.zaxis , ( scale * rot_var ).degrees
                    
                    end

                    # Apply the scaling
                    t_sca = Geom::Transformation.scaling cen , 1 + x_var * (scale - 0.5) , 1 + y_var * (scale - 0.5) , 1 + z_var * (scale - 0.5)
                    e.transform! ( t_rot * t_sca )
                    
                    # Life is always better with some feedback while SketchUp works
                    Sketchup.status_text = toolname + " | Done with object #{(i+1).to_s}"

                }

                # Explode group once we are done
                gr.explode            
            
            rescue Exception => e    
            
                UI.messagebox("Couldn't do it! Error: #{e}")
                
            end
            
            mod.commit_operation
            
        else  # Can't start tool
        
            UI.messagebox "Select several objects (groups or component instances) first. You will be asked to select the image second."
        
        end            
    
    end  # scale_by_image
    
    
    # ==================
    
    
    def self.vertices_by_image
    # Move vertices based on image grayscale
    
        mod = Sketchup.active_model
        ent = mod.entities
        sel = mod.selection
        
        toolname = "Move Vertices by Image"      
        
        # Get all selected edges
        all_edges = mod.selection.grep( Sketchup::Edge )
        
        if !all_edges.empty?
        
            # Get all the parameters from input dialog
            prompts = [ "MAX Variation RED (x distance) " , 
                        "MAX Variation GREEN (y distance) " , 
                        "MAX Variation BLUE (z distance) " ,
                        "Image Orientation " ]
            defaults = [ "0" , "0" , "1'" , "RED-GREEN (x-y)" ]
            lists = [ "" , "" , "" , "RED-GREEN (x-y)|RED-BLUE (x-z)|GREEN-BLUE (y-z)" ]
            res = UI.inputbox( prompts , defaults , lists , toolname )
            return if !res
            
            mod.start_operation toolname
            
            begin
            
                # Get max distances and convert to length
                max_x = res[0].to_l
                max_y = res[1].to_l
                max_z = res[2].to_l

                # Ask for an image file
                f = UI.openpanel 'Select an image file', '', 'Image Files|*.jpg;*.png;||'
                return if f == nil

                # Now load the image
                ir = Sketchup::ImageRep.new
                ir.load_file( f )
                
                # Get all the unique vertices
                vertices = []
                all_edges.each { |e| vertices << e.vertices }
                vertices.flatten!
                vertices.uniq!
                
                # Create temporary group from selection to get dimensions
                gr = ent.add_group( all_edges )
                min = gr.bounds.min
                max = gr.bounds.max    
                gr.explode

                vertices.each_with_index { |v,i| 
                
                    # Scale based on position and image grey value
                    pos = v.position - min
                    
                    # Scale based on orientation
                    if res[3] == "RED-BLUE (x-z)"  # Front orientation
                    
                        width = ( max - min ).x.to_f
                        height = ( max - min ).z.to_f   
                    
                        x = pos.x.to_f / width * ir.width
                        z = pos.z.to_f / height * ir.height
                    
                        scale = self.grey( ir.color_at_uv( x / ir.width , z / ir.height, true) )                   
                    
                    elsif res[3] == "GREEN-BLUE (y-z)"  # Side orientation
                    
                        width = ( max - min ).y.to_f
                        height = ( max - min ).z.to_f   
                    
                        y = pos.y.to_f / width * ir.width
                        z = pos.z.to_f / height * ir.height
                    
                        scale = self.grey( ir.color_at_uv( y / ir.width , z / ir.height, true) )
                    
                    else  # Flat on the ground
                    
                        width = ( max - min ).x.to_f
                        height = ( max - min ).y.to_f   
                    
                        x = pos.x.to_f / width * ir.width
                        y = pos.y.to_f / height * ir.height
                    
                        scale = self.grey( ir.color_at_uv( x / ir.width , y / ir.height, true) )
                    
                    end

                    t = Geom::Transformation.new [ ( scale - 0.5 ) * max_x , ( scale - 0.5 ) * max_y , ( scale - 0.5 ) * max_z ]
                    ent.transform_entities( t , v )
                    
                    # Life is always better with some feedback while SketchUp works
                    Sketchup.status_text = toolname + " | Done with vertex #{(i+1).to_s}"
                    
                }                          
            
            rescue Exception => e    
            
                UI.messagebox("Couldn't do it! Error: #{e}")
                
            end
            
            mod.commit_operation
            
        else  # Can't start tool
        
            UI.messagebox "Select several edges first (their vertices will be moved). You will be asked to select the image second."
        
        end            
    
    end  # vertices_by_image    


    # ==================
    
    
    def self.show_url( title , url )
    # Show website either as a WebDialog or HtmlDialog
    
      if Sketchup.version.to_f < 17 then   # Use old dialog
        @dlg = UI::WebDialog.new( title , true ,
          title.gsub(/\s+/, "_") , 1000 , 600 , 100 , 100 , true);
        @dlg.navigation_buttons_enabled = false
        @dlg.set_url( url )
        @dlg.show      
      else   #Use new dialog
        @dlg = UI::HtmlDialog.new( { :dialog_title => title, :width => 1000, :height => 600,
          :style => UI::HtmlDialog::STYLE_DIALOG, :preferences_key => title.gsub(/\s+/, "_") } )
        @dlg.set_url( url )
        @dlg.show
        @dlg.center
      end  
    
    end    


    def self.show_help
    # Browse news using webdialog
    
      show_url( @exttitle , "http://sketchupfordesign.com/news-display/" ) 

    end # show_help


    # ==================


    if !file_loaded?(__FILE__)

      # Add to the SketchUp help menu
      UI.menu("Plugins").add_item("Scale by Image") { self.scale_by_image }
      UI.menu("Plugins").add_item("Move Vertices by Image") { self.vertices_by_image }

      # Let Ruby know we have loaded this file
      file_loaded(__FILE__)

    end # if


    # ==================


  end # module AS_ScaleBy

end # module AS_Extensions


# ==================
