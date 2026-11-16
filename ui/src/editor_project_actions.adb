with Ada.Characters.Handling;
with Ada.Characters.Latin_1;
with Ada.Directories;
with Ada.Strings.Fixed;
with Adi.App;
with Adi.Core; use Adi.Core;
with Adi.SDL.Video;
with Interfaces.C.Extensions;
with Interfaces.C.Strings;
with Editor_Console;
with Editor_Export;
with Editor_Preferences;
with Editor_Timeline_Actions;
with Editor_Dialogs; use Editor_Dialogs;
with Editor_Controller; use Editor_Controller;

package body Editor_Project_Actions is
   use type US.Unbounded_String;

   procedure Continue_Action;

   --  SDL provides the native title setter absent from the pinned toolkit.
   function Set_Window_Title
     (Window : Adi.SDL.Video.SDL_Window_Ptr;
      Title : Interfaces.C.Strings.chars_ptr) return Interfaces.C.Extensions.bool
     with Import, Convention => C, External_Name => "SDL_SetWindowTitle";

   procedure Update_Title is
      Title : Interfaces.C.Strings.chars_ptr := Interfaces.C.Strings.New_String
        ("Framewise" & (if US.Length (Project_Path) = 0 then "" else
          " " & Ada.Directories.Base_Name (US.To_String (Project_Path))));
      Updated : constant Interfaces.C.Extensions.bool :=
        Set_Window_Title (Get_SDL_Window (W), Title);
      pragma Unreferenced (Updated);
   begin
      Dirty := History /= Saved_History;
      Interfaces.C.Strings.Free (Title);
   end Update_Title;

   procedure Save_Selected (Files : Adi.OS.String_Array) is
   begin
      if Files'Length = 0 then
         return;
      end if;
      declare
         Raw : constant String := US.To_String (Files (Files'First));
         Path : constant String := (if Raw'Length >= 3 and then Raw (Raw'Last - 2 .. Raw'Last) = ".fw"
                                    then Raw else Raw & ".fw");
      begin
         if not Valid_Path (Path, "Save Project") then
            return;
         end if;
         Execute_Line ("save " & FS.Quote_Path (Path));
         if Reply.Ok then
            Project_Path := US.To_Unbounded_String (Path);
            Saved_History := History;
            Update_Title;
            Tell ("Project saved.");
         end if;
      end;
   end Save_Selected;

   procedure Save_Project (Save_As : Boolean := False) is
   begin
      if Save_As or else US.Length (Project_Path) = 0 then
         Adi.OS.Show_Save_File_Dialog (Save_Selected'Access, W,
           Default_Location => (if US.Length (Project_Path) = 0 then "project.fw" else US.To_String (Project_Path)));
      else
         Execute_Line ("save " & FS.Quote_Path (US.To_String (Project_Path)));
         if Reply.Ok then
            Saved_History := History;
            Update_Title;
            Tell ("Project saved.");
         end if;
      end if;
   end Save_Project;

   procedure Open_Selected (Files : Adi.OS.String_Array) is
   begin
      if Files'Length = 0 then
         return;
      end if;
      if not Valid_Path (US.To_String (Files (Files'First)), "Open Project") then
         return;
      end if;
      Execute_Line ("load " & FS.Quote_Path (US.To_String (Files (Files'First))));
      --  Load can fail after replaying part of a file; retain the dirty marker.
      if Reply.Ok then
         Project_Path := Files (Files'First);
         Saved_History := History;
         Editor_Timeline_Actions.Reset_View;
         Refresh_Timeline;
         Tell ("Project opened.");
      end if;
   end Open_Selected;

   procedure Execute_Console_Line (Line : String) is
      Separator : Natural := Line'Last + 1;
      Path_First : Natural;
   begin
      declare
         Output : constant String := FS.Export_Output (Line);
      begin
         if Output'Length > 0 then
            Editor_Export.Start (Output, Editor_Console.Console_Command, Line);
            return;
         end if;
      end;
      Execute_Console_Command (Line);
      if not Reply.Ok then
         return;
      end if;

      --  The session handles parsing and execution. Only successful save/load
      --  commands need extra UI bookkeeping, just like the File menu actions.
      for I in Line'Range loop
         if Line (I) in ' ' | Ada.Characters.Latin_1.HT then
            Separator := I;
            exit;
         end if;
      end loop;
      Path_First := Separator;
      while Path_First <= Line'Last and then
        Line (Path_First) in ' ' | Ada.Characters.Latin_1.HT
      loop
         Path_First := Path_First + 1;
      end loop;
      declare
         Verb : constant String := Ada.Characters.Handling.To_Lower
           (Line (Line'First .. Separator - 1));
      begin
         if Verb in "save" | "load" then
            declare
               Raw : constant String := Ada.Strings.Fixed.Trim
                 (Line (Path_First .. Line'Last), Ada.Strings.Both);
            begin
               --  Store the filename, not its command-language delimiters.
               Project_Path := US.To_Unbounded_String
                 ((if Raw'Length >= 2 and then Raw (Raw'First) = '"'
                   then Raw (Raw'First + 1 .. Raw'Last - 1) else Raw));
            end;
            Saved_History := History;
            if Verb = "load" then
               Editor_Timeline_Actions.Reset_View;
            end if;
            Refresh_Timeline;
         end if;
      end;
   end Execute_Console_Line;

   procedure Continue_Action is
      Action : constant Pending_Action := Pending;
   begin
      Pending := Nothing;
      case Action is
         when New_Project =>
            --  Reset through the same visible commands available in the CLI.
            while FS.History_Length (Editor) > 0 loop
               Execute_Line ("undo");
               exit when not Reply.Ok;
            end loop;
            Project_Path := US.Null_Unbounded_String;
            Saved_History := History;
            Editor_Timeline_Actions.Reset_View;
            Refresh_Timeline;
            Tell ("New project. Import files and add a track to begin.");
         when Open_Project =>
            Adi.OS.Show_Open_File_Dialog (Open_Selected'Access, W,
              Filters => [(US.To_Unbounded_String ("Framewise projects"), US.To_Unbounded_String ("fw"))]);
         when Close_Editor =>
            Editor_Preferences.Capture (W);
            Allow_Close := True;
            Adi.App.Request_Quit;
         when Nothing => null;
      end case;
   end Continue_Action;

   procedure Request_Action (Action : Pending_Action) is
   begin
      Pending := Action;
      if Dirty then
         Dialogs.Show (Confirm);
      else
         Continue_Action;
      end if;
   end Request_Action;

   procedure Confirm_Result (Dialog : Widget_Handle; Index : Natural; Caption : String) is
      pragma Unreferenced (Dialog, Caption);
   begin
      if Index = 1 then
         Continue_Action;
      else
         Pending := Nothing;
      end if;
   end Confirm_Result;

   procedure Close_Requested (Window : Window_Handle; Allow : in out Boolean) is
      pragma Unreferenced (Window);
   begin
      Editor_Preferences.Capture (W);
      if Editor_Export.Is_Busy then
         Allow := False;
         Tell ("Please wait for the export to finish before closing.");
      elsif Dirty and then not Allow_Close then
         Allow := False;
         Request_Action (Close_Editor);
      end if;
   end Close_Requested;

   procedure Export_Selected (Files : Adi.OS.String_Array) is
   begin
      if Files'Length > 0 and then Valid_Path (US.To_String (Files (Files'First)), "Export Video") then
         Editor_Export.Start (US.To_String (Files (Files'First)));
      end if;
   end Export_Selected;

   procedure Reset_File_Menu is
   begin
      --  Recreate the rows to clear the toolkit's retained click/keyboard
      --  selection before reopening this transient action menu.
      Menus.Clear_Items (File_Menu);
      Menus.Add_Item (File_Menu, "New Project     Ctrl+N");
      Menus.Add_Item (File_Menu, "Open Project    Ctrl+O");
      Menus.Add_Item (File_Menu, "Save            Ctrl+S");
      Menus.Add_Item (File_Menu, "Save As   Ctrl+Shift+S");
      Menus.Add_Item (File_Menu, "Import Files...");
      Menus.Add_Item (File_Menu, "Project Settings...");
      Menus.Add_Item (File_Menu, "Export Video...");
      Menus.Add_Item (File_Menu, "Exit");
   end Reset_File_Menu;

   procedure Menu_Selected (Menu : Menus.Menu_Handle; Index : Positive; Text : String) is
      pragma Unreferenced (Menu, Text);
   begin
      case Index is
         when 1 => Request_Action (New_Project);
         when 2 => Request_Action (Open_Project);
         when 3 => Save_Project;
         when 4 => Save_Project (True);
         when 5 => Adi.OS.Show_Open_File_Dialog (Import_Selected'Access, W);
         when 6 =>
            Prepare_Form (Project_Settings, "Project Settings");
            Set_Field (1, "Width (pixels)", FS.Settings_Of (Editor).Width'Image);
            Set_Field (2, "Height (pixels)", FS.Settings_Of (Editor).Height'Image);
            Set_Field (3, "Frames per second", FS.Settings_Of (Editor).FPS'Image);
            Dialogs.Show (Form);
         when 7 => Adi.OS.Show_Save_File_Dialog
           (Export_Selected'Access, W, Default_Location => "out.mp4");
         when 8 => Request_Action (Close_Editor);
         when others => null;
      end case;
   end Menu_Selected;

   procedure Show_File_Menu (Button : Widget_Handle) is
      G : constant Rectangle := Get_Geometry (Button);
   begin
      Reset_File_Menu;
      Menus.Show_At (File_Menu, G.X, G.Y + G.Height, 230.0);
   end Show_File_Menu;
end Editor_Project_Actions;
