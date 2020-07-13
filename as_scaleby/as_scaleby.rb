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
    
        # Give warning where ImageRep isn't available
        if Sketchup.version.to_i < 18
            UI.messagebox "This tool works only with SketchUp 2018 and newer."
            return
        end    
    
        mod = Sketchup.active_model
        ent = mod.entities
        sel = mod.selection
        
        toolname = "Transform Objects by Image"      
        
        # Get all objects from selection
        all_objects = []
        all_objects.push( *sel.grep( Sketchup::ComponentInstance ) )
        all_objects.push( *sel.grep( Sketchup::Group ) )
        
        if !all_objects.empty?
        
            # Get all the parameters from input dialog
            prompts = [ "Transformation to apply (object coords) " ,
                        "Image Orientation (local coords) " ,
                        "Multiplier (scale|angle|distance) " ]
            defaults = [ "Uniform Scaling" , "RED-GREEN (x-y)" , "2" ]
            lists = [ "Uniform Scaling|Scaling in RED|Scaling in GREEN|Scaling in BLUE|Rotation about RED|Rotation about GREEN|Rotation about BLUE|Motion in RED|Motion in GREEN|Motion in BLUE" , 
                      "RED-GREEN (x-y)|RED-BLUE (x-z)|GREEN-BLUE (y-z)" , "" ]
            defaults = Sketchup.read_default( @extname , __method__.to_s , defaults )
            
            res = UI.inputbox( prompts , defaults , lists , toolname )
            return if !res
            
            Sketchup.write_default( @extname , __method__.to_s , res.map { |s| s.gsub( '"' , '' ) } )  # Fix for inch pref saving error
            
            mod.start_operation toolname
            
            begin
            
                if res[0].include? "Motion"
                    s_fac = res[2].to_l 
                else
                    s_fac = res[2].to_f
                end
                
                # Ask for an image file
                f = UI.openpanel 'Select an image file', '', 'Image Files|*.jpg;*.png;||'
                return if f == nil

                # Now load the image
                ir = Sketchup::ImageRep.new
                ir.load_file( f )                

                # Create temporary group from selection to get dimensions
                gr = ent.add_group( all_objects )
                gr_x_dim = ( gr.definition.bounds.max - gr.definition.bounds.min ).x
                gr_y_dim = ( gr.definition.bounds.max - gr.definition.bounds.min ).y
                gr_z_dim = ( gr.definition.bounds.max - gr.definition.bounds.min ).z 

                # Work with entities in group
                gr.entities.each_with_index { |e,i|
                
                    # Get center of object
                    if e.is_a? Sketchup::ComponentInstance
                        cen = e.transformation.origin
                    else
                        cen = e.bounds.center
                    end
                    
                    # Scale based on image orientation
                    if res[1] == "RED-BLUE (x-z)"  # Front orientation
                        
                        x = cen.x.to_f / gr_x_dim
                        z = cen.z.to_f / gr_z_dim

                        scale = self.grey( ir.color_at_uv( x , z , true ) )     
                    
                    elsif res[1] == "GREEN-BLUE (y-z)"  # Side orientation
                        
                        y = cen.y.to_f / gr_y_dim
                        z = cen.z.to_f / gr_z_dim

                        scale = self.grey( ir.color_at_uv( y , z , true ) )      
                    
                    else  # Flat on the ground

                        x = cen.x.to_f / gr_x_dim
                        y = cen.y.to_f / gr_y_dim

                        scale = self.grey( ir.color_at_uv( x , y , true ) )     
                    
                    end       
                    
                    # Get transformation                             
                    if res[0] == "Scaling in RED"

                        t = Geom::Transformation.scaling scale * s_fac , 1 , 1

                    elsif res[0] == "Scaling in GREEN"

                        t = Geom::Transformation.scaling 1 , scale * s_fac , 1

                    elsif res[0] == "Scaling in BLUE"

                        t = Geom::Transformation.scaling 1 , 1 , scale * s_fac                    

                    elsif res[0] == "Rotation about RED"

                        t = Geom::Transformation.rotation [ 0 , 0 , 0 ] , [ 1 , 0 , 0 ] , ( scale * s_fac ).degrees

                    elsif res[0] == "Rotation about GREEN"

                        t = Geom::Transformation.rotation [ 0 , 0 , 0 ] , [ 0 , 1 , 0 ] , ( scale * s_fac ).degrees

                    elsif res[0] == "Rotation about BLUE"

                        t = Geom::Transformation.rotation [ 0 , 0 , 0 ] , [ 0 , 0 , 1 ] , ( scale * s_fac ).degrees

                    elsif res[0] == "Motion in RED"

                        t = Geom::Transformation.translation [ scale * s_fac , 0 , 0 ]

                    elsif res[0] == "Motion in GREEN"

                        t = Geom::Transformation.translation [ 0 , scale * s_fac , 0 ]

                    elsif res[0] == "Motion in BLUE"

                        t = Geom::Transformation.translation [ 0 , 0 , scale * s_fac ]                        

                    else

                        # Uniform scaling as default
                        t = Geom::Transformation.scaling scale * s_fac

                    end

                    # Apply the transformation
                    e.transformation *= t
                    
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
        
            UI.messagebox "Select several objects (groups or component instances) first."
        
        end               
    
    end  # scale_by_image
    
    
    # ==================
    
    
    def self.scale_by_attractor
    # Scale objects based on proximity to attractors
    
        mod = Sketchup.active_model
        ent = mod.entities
        sel = mod.selection
        
        toolname = "Transform Objects by Attractors"      
        
        # Get all objects from selection
        all_objects = []
        all_objects.push( *sel.grep( Sketchup::ComponentInstance ) )
        all_objects.push( *sel.grep( Sketchup::Group ) )
        
        # Get attractors from selection
        att = all_objects.grep( Sketchup::ComponentInstance ) { |c| c if c.definition.name == "A" }
        att.compact!
        
        all_objects = all_objects - att
        
        if !( all_objects.empty? or att.empty? )
        
            # Get all the parameters from input dialog
            prompts = [ "Transformation to apply (object coords) " ,
                        "Attraction Scaling (distance) " ,
                        "Attraction Falloff " ,
                        "Attraction Type " ,
                        "Multiplier (scale|angle|distance) " ]
            defaults = [ "Uniform Scaling" , "10'" , "Linear" , "Decrease" , "2" ]
            lists = [ "Uniform Scaling|Scaling in RED|Scaling in GREEN|Scaling in BLUE|Rotation about RED|Rotation about GREEN|Rotation about BLUE|Motion in RED|Motion in GREEN|Motion in BLUE" , 
                      "" , "Root|Linear|Square" , "Decrease|Increase" , "" ]
            defaults = Sketchup.read_default( @extname , __method__.to_s , defaults )
            
            res = UI.inputbox( prompts , defaults , lists , toolname )
            return if !res
            
            Sketchup.write_default( @extname , __method__.to_s , res.map { |s| s.gsub( '"' , '' ) } )  # Fix for inch pref saving error
            
            mod.start_operation toolname
            
            begin
            
                # Get parameters
                att_val = res[1].to_l 
                if res[2] == "Root"
                    power = 0.5
                elsif res[2] == "Square"
                    power = 2
                else
                    power = 1
                end  
                if res[0].include? "Motion"
                    s_fac = res[4].to_l 
                else
                    s_fac = res[4].to_f
                end

                # Create temporary group from selection to get dimensions
                gr = ent.add_group( all_objects + att )
                gr_x_dim = ( gr.definition.bounds.max - gr.definition.bounds.min ).x
                gr_y_dim = ( gr.definition.bounds.max - gr.definition.bounds.min ).y
                gr_z_dim = ( gr.definition.bounds.max - gr.definition.bounds.min ).z 

                # Work with entities in group
                gr.entities.each_with_index { |e,i|
                
                    if !att.include?(e)
                
                        # Get center of object
                        if e.is_a? Sketchup::ComponentInstance
                            cen = e.transformation.origin
                        else
                            cen = e.bounds.center
                        end
                        
                        # Find the smallest attractor distance, start with large number
                        dist = 1000000
                        
                        att.each { |a|
                        
                            a_dist = a.transformation.origin.distance cen
                            dist = a_dist if a_dist < dist
                        
                        }
                        
                        scale = ( dist**power / att_val**power ).to_f
                        
                        # Adjust up/down scaling direction                        
                        scale = 1 / scale if res[3] == "Increase"

                        # Get transformation                             
                        if res[0] == "Scaling in RED"

                            t = Geom::Transformation.scaling scale * s_fac , 1 , 1

                        elsif res[0] == "Scaling in GREEN"

                            t = Geom::Transformation.scaling 1 , scale * s_fac , 1

                        elsif res[0] == "Scaling in BLUE"

                            t = Geom::Transformation.scaling 1 , 1 , scale * s_fac                    

                        elsif res[0] == "Rotation about RED"

                            t = Geom::Transformation.rotation [ 0 , 0 , 0 ] , [ 1 , 0 , 0 ] , ( scale * s_fac ).degrees

                        elsif res[0] == "Rotation about GREEN"

                            t = Geom::Transformation.rotation [ 0 , 0 , 0 ] , [ 0 , 1 , 0 ] , ( scale * s_fac ).degrees

                        elsif res[0] == "Rotation about BLUE"

                            t = Geom::Transformation.rotation [ 0 , 0 , 0 ] , [ 0 , 0 , 1 ] , ( scale * s_fac ).degrees

                        elsif res[0] == "Motion in RED"

                            t = Geom::Transformation.translation [ scale * s_fac , 0 , 0 ]

                        elsif res[0] == "Motion in GREEN"

                            t = Geom::Transformation.translation [ 0 , scale * s_fac , 0 ]

                        elsif res[0] == "Motion in BLUE"

                            t = Geom::Transformation.translation [ 0 , 0 , scale * s_fac ]                        

                        else

                            # Uniform scaling as default
                            t = Geom::Transformation.scaling scale * s_fac

                        end

                        # Apply the transformation
                        e.transformation *= t

                        # Life is always better with some feedback while SketchUp works
                        Sketchup.status_text = toolname + " | Done with object #{(i+1).to_s}"
                        
                    end

                }

                # Explode group once we are done
                gr.explode            
            
            rescue Exception => e    
            
                UI.messagebox("Couldn't do it! Error: #{e}")
                
            end
            
            mod.commit_operation
            
        else  # Can't start tool
        
            UI.messagebox "Select several objects (groups or component instances) and one or more components named 'A' first."
        
        end               
    
    end  # scale_by_attractor    
    
    
    # ==================
    
    
    def self.pushpull_by_image
    # Push/pull faces based on image grayscale
    
        # Give warning where ImageRep isn't available
        if Sketchup.version.to_i < 18
            UI.messagebox "This tool works only with SketchUp 2018 and newer."
            return
        end    
    
        mod = Sketchup.active_model
        ent = mod.entities
        sel = mod.selection
        
        toolname = "Push/Pull Faces by Image"     
        
        # Get all faces from selection
        all_faces = sel.grep( Sketchup::Face )
        
        if !all_faces.empty?
        
            # Get all the parameters from input dialog
            prompts = [ "MIN Extrusion (distance) " , 
                        "MAX Extrusion (distance) " , 
                        "Create New Faces " ,
                        "Image Orientation (local coords) " ]
            defaults = [ "0" , "1'" , "Yes" , "RED-GREEN (x-y)" ]
            lists = [ "" , "" , "Yes|No" , "RED-GREEN (x-y)|RED-BLUE (x-z)|GREEN-BLUE (y-z)" ]
            defaults = Sketchup.read_default( @extname , __method__.to_s , defaults )
            
            res = UI.inputbox( prompts , defaults , lists , toolname )
            return if !res
            
            Sketchup.write_default( @extname , __method__.to_s , res.map { |s| s.gsub( '"' , '' ) } )  # Fix for inch pref saving error
            
            mod.start_operation toolname
            
            begin
            
                # Get extrusion distances and convert to length
                min_pp = res[0].to_l
                max_pp = res[1].to_l

                # Ask for an image file
                f = UI.openpanel 'Select an image file', '', 'Image Files|*.jpg;*.png;||'
                return if f == nil

                # Now load the image
                ir = Sketchup::ImageRep.new
                ir.load_file( f )

                # Create temporary group from selection to get dimensions
                gr = ent.add_group( all_faces )
                gr_x_dim = ( gr.definition.bounds.max - gr.definition.bounds.min ).x
                gr_y_dim = ( gr.definition.bounds.max - gr.definition.bounds.min ).y
                gr_z_dim = ( gr.definition.bounds.max - gr.definition.bounds.min ).z

                # Work with all faces
                all_faces.each_with_index { |e,i|
                
                    # Get center of face
                    cen = e.bounds.center
                    
                    # Scale based on orientation
                    if res[3] == "RED-BLUE (x-z)"  # Front orientation
                    
                        x = cen.x.to_f / gr_x_dim
                        z = cen.z.to_f / gr_z_dim

                        scale = self.grey( ir.color_at_uv( x , z , true ) )                     
                    
                    elsif res[3] == "GREEN-BLUE (y-z)"  # Side orientation
                    
                        y = cen.y.to_f / gr_y_dim
                        z = cen.z.to_f / gr_z_dim

                        scale = self.grey( ir.color_at_uv( y , z , true ) )     
                    
                    else  # Flat on the ground
                    
                        x = cen.x.to_f / gr_x_dim
                        y = cen.y.to_f / gr_y_dim

                        scale = self.grey( ir.color_at_uv( x , y , true ) )      
                    
                    end
                    
                    # Extrude face
                    e.pushpull( min_pp + scale * ( max_pp - min_pp ) , res[2] == "Yes" ? true : false )      
                    
                    # Life is always better with some feedback while SketchUp works
                    Sketchup.status_text = toolname + " | Done with face #{(i+1).to_s}"

                }     
                
                # Explode group once we are done
                gr.explode                 
            
            rescue Exception => e    
            
                UI.messagebox("Couldn't do it! Error: #{e}")
                
            end 
            
            mod.commit_operation
            
        else  # Can't start tool
        
            UI.messagebox "Select several faces first. You will be asked to select the image second."
        
        end            
    
    end  # pushpull_by_image    
    
    
    # ==================
    
    
    def self.vertices_by_image
    # Move vertices based on image grayscale
    
        # Give warning where ImageRep isn't available
        if Sketchup.version.to_i < 18
            UI.messagebox "This tool works only with SketchUp 2018 and newer."
            return
        end    
    
        mod = Sketchup.active_model
        ent = mod.entities
        sel = mod.selection
        
        toolname = "Move Vertices by Image"      
        
        # Get all selected edges (and faces if we have some)
        all_edges = mod.selection.grep( Sketchup::Edge )
        all_faces = mod.selection.grep( Sketchup::Face )
        
        if !all_edges.empty?
        
            # Get all the parameters from input dialog
            prompts = [ "MAX Motion in RED (x distance) " , 
                        "MAX Motion in GREEN (y distance) " , 
                        "MAX Motion in BLUE (z distance) " ,
                        "Image Orientation (all in local coords) " ]
            defaults = [ "0" , "0" , "1'" , "RED-GREEN (x-y)" ]
            lists = [ "" , "" , "" , "RED-GREEN (x-y)|RED-BLUE (x-z)|GREEN-BLUE (y-z)" ]
            defaults = Sketchup.read_default( @extname , __method__.to_s , defaults )
            
            res = UI.inputbox( prompts , defaults , lists , toolname )
            return if !res
            
            Sketchup.write_default( @extname , __method__.to_s , res.map { |s| s.gsub( '"' , '' ) } )  # Fix for inch pref saving error
            
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
             
                # Create temporary group from selection to get dimensions
                gr = ent.add_group( all_edges + all_faces ) 
                gr_x_dim = ( gr.definition.bounds.max - gr.definition.bounds.min ).x
                gr_y_dim = ( gr.definition.bounds.max - gr.definition.bounds.min ).y
                gr_z_dim = ( gr.definition.bounds.max - gr.definition.bounds.min ).z    
           
                # Get all the unique vertices                
                gr_edges = gr.entities.grep( Sketchup::Edge )
                vertices = []
                gr_edges.each { |e| vertices << e.vertices }
                vertices.flatten!
                vertices.uniq!

                vertices.each_with_index { |v,i| 
                
                    # Scale based on position and image grey value
                    cen = v.position
                    
                    # Scale based on orientation
                    if res[3] == "RED-BLUE (x-z)"  # Front orientation
                    
                        x = cen.x.to_f / gr_x_dim
                        z = cen.z.to_f / gr_z_dim

                        scale = self.grey( ir.color_at_uv( x , z , true ) )                     
                    
                    elsif res[3] == "GREEN-BLUE (y-z)"  # Side orientation
                    
                        y = cen.y.to_f / gr_y_dim
                        z = cen.z.to_f / gr_z_dim

                        scale = self.grey( ir.color_at_uv( y , z , true ) )    
                    
                    else  # Flat on the ground
                    
                        x = cen.x.to_f / gr_x_dim
                        y = cen.y.to_f / gr_y_dim

                        scale = self.grey( ir.color_at_uv( x , y , true ) )  
                    
                    end

                    t = Geom::Transformation.new [  scale * max_x , scale * max_y , scale * max_z ]
                    gr.entities.transform_entities( t , v )
                    
                    # Life is always better with some feedback while SketchUp works
                    Sketchup.status_text = toolname + " | Done with vertex #{(i+1).to_s}"
                    
                }
                
                # Explode group once we are done
                gr.explode  
            
            rescue Exception => e    
            
                UI.messagebox("Couldn't do it! Error: #{e}")
                
            end
            
            mod.commit_operation
            
        else  # Can't start tool
        
            UI.messagebox "Select several edges (and faces if connected) first (their vertices will be moved). You will be asked to select the image second."
        
        end            
    
    end  # vertices_by_image    
    
    
    # ==================
    
    
    def self.scale_by_math_power
    # Scale objects based on a math formula
    
        mod = Sketchup.active_model
        ent = mod.entities
        sel = mod.selection
        
        toolname = "Transform Objects by Power Equation"      
        
        # Get all objects from selection
        all_objects = []
        all_objects.push( *sel.grep( Sketchup::ComponentInstance ) )
        all_objects.push( *sel.grep( Sketchup::Group ) )
        
        if !all_objects.empty?
        
            # Get all the parameters from input dialog
            prompts = [ "Transformation to apply (object coords) " ,
                        "Multiplier in RED (x) (A in f = A(Bx)^C+D) " , 
                        "Power Factor in RED (x) (B in f = A(Bx)^C+D) " ,
                        "Power in RED (x) (C in f = A(Bx)^C+D) " ,
                        "Multiplier in GREEN (y) (A in f = A(By)^C+D) " , 
                        "Power Factor in GREEN (y) (B in f = A(By)^C+D) " ,
                        "Power in GREEN (y) (C in f = A(By)^C+D) " ,
                        "Multiplier in BLUE (z) (A in f = A(Bz)^C+D) " , 
                        "Power Factor in BLUE (z) (B in f = A(Bz)^C+D) " ,
                        "Power in BLUE (z) (C in f = A(Bz)^C+D) " ,
                        "Offset (D) (all in local coords) " ]
            defaults = [ "Uniform Scaling" , "1" , "2" , "2" , "1" , "2" , "2" , "0" , "0" , "0" , "0" ]
            lists = [ "Uniform Scaling|Scaling in RED|Scaling in GREEN|Scaling in BLUE|Rotation about RED|Rotation about GREEN|Rotation about BLUE|Motion in RED|Motion in GREEN|Motion in BLUE" , "" , "" , "" , "" , "" , "" , "" , "" , "" , "" ]
            defaults = Sketchup.read_default( @extname , __method__.to_s , defaults )
            
            res = UI.inputbox( prompts , defaults , lists , toolname )
            return if !res
            
            Sketchup.write_default( @extname , __method__.to_s , res.map { |s| s.gsub( '"' , '' ) } )  # Fix for inch pref saving error
            
            mod.start_operation toolname
            
            begin
            
                x_fac = res[1].to_f
                y_fac = res[4].to_f
                z_fac = res[7].to_f
                x_pfa = res[2].to_f
                y_pfa = res[5].to_f
                z_pfa = res[8].to_f                
                x_pow = res[3].to_f
                y_pow = res[6].to_f
                z_pow = res[9].to_f
                off = res[10].to_f

                # Create temporary group from selection to get dimensions
                gr = ent.add_group( all_objects )
                gr_x_dim = ( gr.definition.bounds.max - gr.definition.bounds.min ).x
                gr_y_dim = ( gr.definition.bounds.max - gr.definition.bounds.min ).y
                gr_z_dim = ( gr.definition.bounds.max - gr.definition.bounds.min ).z 

                # Work with entities in group
                gr.entities.each_with_index { |e,i|
                
                    # Get base of object
                    if e.is_a? Sketchup::ComponentInstance
                        cen = e.transformation.origin
                    else
                        cen = e.bounds.center
                    end
                    
                    # Get combined scale
                    scale = 0.0
                    scale += x_fac * ( x_pfa * ( cen.x / gr_x_dim - 0.5)) ** x_pow  if gr_x_dim.abs > 0
                    scale += y_fac * ( y_pfa * ( cen.y / gr_y_dim - 0.5)) ** y_pow  if gr_y_dim.abs > 0
                    scale += z_fac * ( z_pfa * ( cen.z / gr_z_dim - 0.5)) ** z_pow  if gr_z_dim.abs > 0
                    scale += off
                    
                    # Get transformation                             
                    if res[0] == "Scaling in RED"

                        t = Geom::Transformation.scaling scale , 1 , 1

                    elsif res[0] == "Scaling in GREEN"

                        t = Geom::Transformation.scaling 1 , scale , 1

                    elsif res[0] == "Scaling in BLUE"

                        t = Geom::Transformation.scaling 1 , 1 , scale                    

                    elsif res[0] == "Rotation about RED"

                        t = Geom::Transformation.rotation [ 0 , 0 , 0 ] , [ 1 , 0 , 0 ] , ( scale ).degrees

                    elsif res[0] == "Rotation about GREEN"

                        t = Geom::Transformation.rotation [ 0 , 0 , 0 ] , [ 0 , 1 , 0 ] , ( scale ).degrees

                    elsif res[0] == "Rotation about BLUE"

                        t = Geom::Transformation.rotation [ 0 , 0 , 0 ] , [ 0 , 0 , 1 ] , ( scale ).degrees

                    elsif res[0] == "Motion in RED"

                        t = Geom::Transformation.translation [ scale , 0 , 0 ]

                    elsif res[0] == "Motion in GREEN"

                        t = Geom::Transformation.translation [ 0 , scale , 0 ]

                    elsif res[0] == "Motion in BLUE"

                        t = Geom::Transformation.translation [ 0 , 0 , scale ]                        

                    else

                        # Uniform scaling as default
                        t = Geom::Transformation.scaling scale

                    end

                    # Apply the transformation
                    e.transformation *= t                    
                    
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
        
            UI.messagebox "Select several objects (groups or component instances) first."
        
        end            
    
    end  # scale_by_math_power  
    
    
    # ==================
    
    
    def self.scale_by_math_sine
    # Scale objects based on a math formula
    
        mod = Sketchup.active_model
        ent = mod.entities
        sel = mod.selection
        
        toolname = "Transform Objects by Sine/Cosine Equation"      
        
        # Get all objects from selection
        all_objects = []
        all_objects.push( *sel.grep( Sketchup::ComponentInstance ) )
        all_objects.push( *sel.grep( Sketchup::Group ) )
        
        if !all_objects.empty?
        
            # Get all the parameters from input dialog
            prompts = [ "Transformation to apply (object coords) " ,
                        "Use " ,
                        "Amplitude in RED (x) (A in f = A*sin(Bx)+D) " , 
                        "Period in RED (x) (B in f = A*sin(Bx)+D) " ,
                        "Amplitude in GREEN (y) (A in f = A*sin(By)+D) " , 
                        "Period in GREEN (y) (B in f = A*sin(By)+D) " ,
                        "Amplitude in BLUE (z) (A in f = A*sin(Bz)+D) " , 
                        "Period in BLUE (z) (B in f = A*sin(Bz)+D) " ,
                        "Offset (D) (all in local coords) " ]
            defaults = [ "Uniform Scaling" , "Sine" , "1" , "1" , "1" , "1" , "0" , "0" , "0" ]
            lists = [ "Uniform Scaling|Scaling in RED|Scaling in GREEN|Scaling in BLUE|Rotation about RED|Rotation about GREEN|Rotation about BLUE|Motion in RED|Motion in GREEN|Motion in BLUE" , "Sine|Cosine" , "" , "" , "" , "" , "" , "" , "" , "" , "" , "" ]
            defaults = Sketchup.read_default( @extname , __method__.to_s , defaults )
            
            res = UI.inputbox( prompts , defaults , lists , toolname )
            return if !res
            
            Sketchup.write_default( @extname , __method__.to_s , res.map { |s| s.gsub( '"' , '' ) } )  # Fix for inch pref saving error
            
            mod.start_operation toolname
            
            begin
            
                x_fac = res[2].to_f
                y_fac = res[4].to_f
                z_fac = res[6].to_f
                x_pfa = res[3].to_f
                y_pfa = res[5].to_f
                z_pfa = res[7].to_f                
                off = res[8].to_f

                # Create temporary group from selection to get dimensions
                gr = ent.add_group( all_objects )
                gr_x_dim = ( gr.definition.bounds.max - gr.definition.bounds.min ).x
                gr_y_dim = ( gr.definition.bounds.max - gr.definition.bounds.min ).y
                gr_z_dim = ( gr.definition.bounds.max - gr.definition.bounds.min ).z 

                # Work with entities in group
                gr.entities.each_with_index { |e,i|
                
                    # Get base of object
                    if e.is_a? Sketchup::ComponentInstance
                        cen = e.transformation.origin
                    else
                        cen = e.bounds.center
                    end
                    
                    # Get combined scale
                    if res[1] == "Cosine"
                    
                        scale = 0.0
                        scale += x_fac * Math::cos( x_pfa * Math::PI * ( cen.x / gr_x_dim - 0.5)) if gr_x_dim.abs > 0
                        scale += y_fac * Math::cos( y_pfa * Math::PI * ( cen.y / gr_y_dim - 0.5)) if gr_y_dim.abs > 0
                        scale += z_fac * Math::cos( z_pfa * Math::PI * ( cen.z / gr_z_dim - 0.5)) if gr_z_dim.abs > 0
                        scale += off                        
                    
                    else
                    
                        scale = 0.0
                        scale += x_fac * Math::sin( x_pfa * Math::PI * ( cen.x / gr_x_dim - 0.5)) if gr_x_dim.abs > 0
                        scale += y_fac * Math::sin( y_pfa * Math::PI * ( cen.y / gr_y_dim - 0.5)) if gr_y_dim.abs > 0
                        scale += z_fac * Math::sin( z_pfa * Math::PI * ( cen.z / gr_z_dim - 0.5)) if gr_z_dim.abs > 0
                        scale += off    
                    
                    end
                    
                    # Get transformation                             
                    if res[0] == "Scaling in RED"

                        t = Geom::Transformation.scaling scale , 1 , 1

                    elsif res[0] == "Scaling in GREEN"

                        t = Geom::Transformation.scaling 1 , scale , 1

                    elsif res[0] == "Scaling in BLUE"

                        t = Geom::Transformation.scaling 1 , 1 , scale                    

                    elsif res[0] == "Rotation about RED"

                        t = Geom::Transformation.rotation [ 0 , 0 , 0 ] , [ 1 , 0 , 0 ] , ( scale ).degrees

                    elsif res[0] == "Rotation about GREEN"

                        t = Geom::Transformation.rotation [ 0 , 0 , 0 ] , [ 0 , 1 , 0 ] , ( scale ).degrees

                    elsif res[0] == "Rotation about BLUE"

                        t = Geom::Transformation.rotation [ 0 , 0 , 0 ] , [ 0 , 0 , 1 ] , ( scale ).degrees

                    elsif res[0] == "Motion in RED"

                        t = Geom::Transformation.translation [ scale , 0 , 0 ]

                    elsif res[0] == "Motion in GREEN"

                        t = Geom::Transformation.translation [ 0 , scale , 0 ]

                    elsif res[0] == "Motion in BLUE"

                        t = Geom::Transformation.translation [ 0 , 0 , scale ]                        

                    else

                        # Uniform scaling as default
                        t = Geom::Transformation.scaling scale

                    end

                    # Apply the transformation
                    e.transformation *= t
                    
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
        
            UI.messagebox "Select several objects (groups or component instances) first."
        
        end            
    
    end  # scale_by_math_sine    


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
    
      show_url( @exttitle , "https://alexschreyer.net/projects/scale-by-image-equation-tools-extension-for-sketchup/" ) 

    end # show_help


    # ==================


    if !file_loaded?(__FILE__)

        tools = []
        tools << [ "Transform Objects by Image" , "scale_by_image" , "Select several objects (groups or component instances) first. You will be asked to select the image second." ]
        tools << [ "Transform Objects by Attractors" , "scale_by_attractor" , "Select several objects (groups or component instances) and one or more components named 'A' first." ]      
        tools << [ "Transform Objects by Power Equation" , "scale_by_math_power" , "Select several objects (groups or component instances) first." ]
        tools << [ "Transform Objects by Sine/Cosine Equation" , "scale_by_math_sine" , "Select several objects (groups or component instances) first." ]
        tools << [ "" , "" , "" ]
        tools << [ "Push/Pull Faces by Image" , "pushpull_by_image" , "Select several faces first. You will be asked to select the image second." ]
        tools << [ "Move Vertices by Image" , "vertices_by_image" , "Select several edges (and faces if connected) first (their vertices will be moved). You will be asked to select the image second." ]

        # Add to the SketchUp Extensions menu and create a toolbar
        menu = UI.menu( "Tools" ).add_submenu( @exttitle )
        toolbar = UI::Toolbar.new @exttitle 
        
        # Get icon file extension
        sm = lg = ""    
        RUBY_PLATFORM =~ /darwin/ ? ext = "pdf" : ext = "svg"
        if Sketchup.version.to_i < 16  
            ext = "png"
            sm = "_sm"
            lg = "_lg"
        end     
        
        # Add them all to menu and toolbar
        tools.each { |t|
        
            if ( t[0] != "" )

                cmd = UI::Command.new( t[0] ) { self.send( t[1] ) }
                cmd.small_icon = File.join( @extdir , @extname , "icons" , t[1] + "#{sm}.#{ext}")
                cmd.large_icon = File.join( @extdir , @extname , "icons" , t[1] + "#{lg}.#{ext}")
                cmd.tooltip = t[0]
                cmd.status_bar_text = t[2]
                menu.add_item cmd
                toolbar.add_item cmd    
                
            else
            
                menu.add_separator
                toolbar.add_separator
            
            end

        }        

        # And a link to get help only to the menu
        menu.add_separator
        menu.add_item( "Help" ) { self.show_help }
        
        
        # Don't forget to show the toolbar
        toolbar.show

        # Let Ruby know we have loaded this file
        file_loaded(__FILE__)

    end # if


    # ==================


  end # module AS_ScaleBy

end # module AS_Extensions


# ==================
