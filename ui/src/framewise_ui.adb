--  A desktop editor shell. All document changes use Session.Execute;
--  selection, tools, zoom and scrubbing remain local UI state.
pragma Ada_2022;

with Ada.Characters.Latin_1;
with Ada.Directories;
with Ada.Strings;
with Ada.Strings.Fixed;
with Ada.Strings.Unbounded;
with Adi.App;
with Adi.Core; use Adi.Core;
with Adi.CSS_Styles; use Adi.CSS_Styles;
with Adi.Layout_Util;
with Adi.OS;
with Adi.SDL.Events;
with Adi.SDL.Video;
with Adi.SDL.Mouse;
with Interfaces.C.Extensions;
with Interfaces.C.Strings;
with Adi.Widget; use Adi.Widget;
with Adi.Widget.Box;
with Adi.Widget.Button;
with Adi.Widget.Combo_Box;
with Adi.Widget.Context_Menu;
with Adi.Widget.Dialog;
with Adi.Widget.Label;
with Adi.Widget.Text_Editor;
with Adi.Widget.Text_Input;
with Adi.Widget_Styles; use Adi.Widget_Styles;
with Adi.Window; use Adi.Window;
with Framewise;
with Framewise.Session;
with Timeline_View;
with Editor_Split;

procedure Framewise_UI is
   package FS renames Framewise.Session;
   package US renames Ada.Strings.Unbounded;
   package Boxes renames Adi.Widget.Box;
   package Buttons renames Adi.Widget.Button;
   package Labels renames Adi.Widget.Label;
   package Inputs renames Adi.Widget.Text_Input;
   package Combos renames Adi.Widget.Combo_Box;
   package Menus renames Adi.Widget.Context_Menu;
   package Dialogs renames Adi.Widget.Dialog;
   use type Framewise.Time;
   use type Boxes.Box_Handle;
   use type Buttons.Button_Handle;
   use type Labels.Label_Handle;
   use type Inputs.Text_Input_Handle;
   use type Combos.Combo_Box_Handle;
   use type Adi.Widget.Text_Editor.Text_Editor_Handle;
   use type Timeline_View.Views.Handle;
   use type Editor_Split.Views.Handle;
   use type Adi.SDL.Events.SDL_Scancode;
   use type US.Unbounded_String;
   --  SDL's USB scancodes; this pinned Adi binding names only some letters.
   Key_N : constant Adi.SDL.Events.SDL_Scancode := 17;
   Key_O : constant Adi.SDL.Events.SDL_Scancode := 18;
   Key_S : constant Adi.SDL.Events.SDL_Scancode := 22;

   A : Adi.App.App;
   W : Window_Handle;
   Editor : FS.Session;
   Reply : FS.Response;
   Tracks : Timeline_View.Views.Handle;
   Preview, Status, Tool_Status : Labels.Label_Handle;
   Sources : Adi.Widget.Text_Editor.Text_Editor_Handle;
   Source_Choice, Track_Choice, Kind_Choice : Combos.Combo_Box_Handle;
   File_Menu : Menus.Menu_Handle;
   Form, Confirm : Dialogs.Dialog_Handle;
   Form_Content : Boxes.Box_Handle;
   type Box_Array is array (Positive range <>) of Boxes.Box_Handle;
   type Dialog_Array is array (Positive range <>) of Dialogs.Dialog_Handle;
   type Input_Array is array (Positive range 1 .. 3) of Inputs.Text_Input_Handle;
   Values : Input_Array;
   type Label_Array is array (Positive range 1 .. 3) of Labels.Label_Handle;
   Captions : Label_Array;
   File_Button, Add_Track_Button, Place_Button, Undo_Button,
     Delete_Button, Razor_Button, Move_Button,
     Zoom_In, Zoom_Out, Scroll_Left, Scroll_Right, Start_Button : Buttons.Button_Handle;
   type Form_Mode is (Import_Media, Add_Track, Place_Clip, Move_Clip, Project_Settings);
   Mode : Form_Mode := Import_Media;
   type Pending_Action is (Nothing, New_Project, Open_Project, Close_Editor);
   Pending : Pending_Action := Nothing;
   Project_Path, Saved_History : US.Unbounded_String;
   Form_Target : US.Unbounded_String;
   Dirty : Boolean := False;
   Allow_Close : Boolean := False;
   Serial : Natural := 0;

   function Style return Style_Builder renames Adi.Widget_Styles.Create;
   Text_Style : constant Style_Rules :=
     (Color => Set (RGB (215, 225, 239)), Font_Size => Set_Font (Px (14.0)), others => <>);
   Panel_Style : constant Style_Rules :=
     (Display => Set (Flex), Flex_Direction => Set (Column),
      Gap => Set (Gap (Px (8.0))), Padding => Set (CSS_Box (Px (12.0))),
      Background_Color => Set_Bg (RGB (20, 26, 36)), others => <>);
   Row_Style : constant Style_Rules :=
     (Display => Set (Flex), Flex_Direction => Set (Row),
      Gap => Set (Gap (Px (6.0))), Flex_Shrink => Set (0.0), others => <>);

   procedure Tell (Text : String) is
   begin
      Labels.Set_Text (Status, Text);
   end Tell;

   function History return US.Unbounded_String is
      Result : US.Unbounded_String;
   begin
      for I in 1 .. FS.History_Length (Editor) loop
         US.Append (Result, FS.History_Line (Editor, I) & Ada.Characters.Latin_1.LF);
      end loop;
      return Result;
   end History;

   --  The pinned toolkit exposes the SDL window but has no title setter.
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

   procedure Style_Button (H : Buttons.Button_Handle) is
   begin
      Set_Part_Style (+H, Main_Part, Style.Base
        ((Background_Color => Set_Bg (RGB (38, 50, 67)),
          Padding => Set (CSS_Box (Px (7.0), Px (10.0))),
          Border_Radius => Set (Radius (Px (3.0))), others => <>)).Build);
      Set_Part_Style (+H, Label_Part, Style.Base (Text_Style).Build);
   end Style_Button;

   procedure Style_Combo (H : Combos.Combo_Box_Handle) is
   begin
      Set_Part_Style (+H, Main_Part, Style.Base
        ((Display => Set (Flex), Flex_Direction => Set (Row),
          Width => Set (Size (Px (200.0))),
          Height => Set (Size (Px (38.0))), Flex_Shrink => Set (0.0),
          Background_Color => Set_Bg (RGB (38, 50, 67)),
          Padding => Set (CSS_Box (Px (6.0))), others => <>)).Build);
      Set_Part_Style (+H, Text_Part, Style.Base (Text_Style).Build);
      Combos.Set_Dropdown_Part_Styles (H,
        (Main_Part => (Style => Style.Base (Panel_Style).Build, Enabled => True), others => <>));
      Combos.Set_Option_Row_Part_Styles (H,
        (Label_Part => (Style => Style.Base (Text_Style).Build, Enabled => True), others => <>));
   end Style_Combo;

   function Read_Sequence return FS.Sequence_View is (FS.Sequence_Of (Editor));

   procedure Show_Preview (Text : String) is
   begin
      Labels.Set_Text (Preview, Text & Ada.Characters.Latin_1.LF &
        "Video frame preview is not available yet.");
   end Show_Preview;

   procedure Refresh_Timeline is
      Seq : constant FS.Sequence_View := FS.Sequence_Of (Editor);
      Text : US.Unbounded_String;
      Old_Source : constant String := Combos.Get_Selected_Text (Source_Choice);
      Old_Track : constant String := Combos.Get_Selected_Text (Track_Choice);
      Rows : Natural := 0;
   begin
      Combos.Clear_Items (Source_Choice);
      Combos.Clear_Items (Track_Choice);
      for Source of Seq.Sources loop
         if Source.Used then
            Combos.Add_Item (Source_Choice, Framewise.Image (Source.N));
            if Framewise.Image (Source.N) = Old_Source then
               Combos.Set_Selected_Index (Source_Choice, Combos.Option_Count (Source_Choice));
            end if;
            US.Append (Text, Framewise.Image (Source.N) & "  |  " & Source.Kind'Image &
              "  |  " & FS.Image_Time (Source.Length) & " s" & Ada.Characters.Latin_1.LF &
              Framewise.Image (Source.File) & Ada.Characters.Latin_1.LF & Ada.Characters.Latin_1.LF);
         end if;
      end loop;
      for Track of Seq.Tracks loop
         if Track.Used then
            Rows := Rows + 1;
            Combos.Add_Item (Track_Choice, Framewise.Image (Track.N));
            if Framewise.Image (Track.N) = Old_Track then
               Combos.Set_Selected_Index (Track_Choice, Combos.Option_Count (Track_Choice));
            end if;
         end if;
      end loop;
      if Combos.Get_Selected_Index (Source_Choice) = 0 then
         Combos.Set_Selected_Index (Source_Choice, Natural'Min (1, Combos.Option_Count (Source_Choice)));
      end if;
      if Combos.Get_Selected_Index (Track_Choice) = 0 then
         Combos.Set_Selected_Index (Track_Choice, Natural'Min (1, Combos.Option_Count (Track_Choice)));
      end if;
      Adi.Widget.Text_Editor.Set_Text (Sources,
        (if US.Length (Text) = 0 then "No project files. Use Import Files to add media."
         else US.To_String (Text)));
      declare
         V : Timeline_View.Views.Ref := Timeline_View.Views.Borrow (Tracks);
      begin
         Show_Preview (Timeline_View.Preview_Text (Seq, V.Playhead));
      end;
      Set_Part_Style (+Tracks, Main_Part, Style.Base
        ((Height => Set (Size (Px (Float (Natural'Max (Rows, 4) * 48 + 36)))),
          Flex_Shrink => Set (0.0), Background_Color => Set_Bg (RGB (29, 38, 51)), others => <>)).Build);
      Update_Title;
      Mark_Dirty (+Tracks);
   end Refresh_Timeline;

   procedure Execute_Line (Line : String) is
   begin
      FS.Execute (Editor, Line, Reply);
      Refresh_Timeline;
      if Reply.Ok then
         Tell ("Edit applied.");
      else
         Tell (FS.Image (Reply));
      end if;
   end Execute_Line;

   --  The shared file format currently uses unquoted tokens. Reject paths
   --  it cannot represent, including shell syntax in ffmpeg output paths.
   function Safe_Path (Text : String) return Boolean is
     (Text'Length > 0 and then Text'Length <= 240 and then
      (for all C of Text => C in 'a' .. 'z' | 'A' .. 'Z' | '0' .. '9' |
        '/' | '\' | ':' | '.' | '_' | '-'));

   function Valid_Path (Text : String) return Boolean is
   begin
      if Safe_Path (Text) then
         return True;
      end if;
      Tell ("Choose a path using letters, numbers, dots, dashes or underscores; spaces are not supported yet.");
      return False;
   end Valid_Path;

   function Unique_Name (Prefix : String) return String is
      Seq : constant FS.Sequence_View := FS.Sequence_Of (Editor);
   begin
      loop
         Serial := Serial + 1;
         declare
            Name : constant String := Prefix & Ada.Strings.Fixed.Trim (Serial'Image, Ada.Strings.Both);
            Found : Boolean := False;
         begin
            for S of Seq.Sources loop
               Found := Found or else (S.Used and then Framewise.Image (S.N) = Name);
            end loop;
            for T of Seq.Tracks loop
               Found := Found or else (T.Used and then Framewise.Image (T.N) = Name);
               for I in 1 .. T.Count loop
                  Found := Found or else Framewise.Image (T.Clips (I).N) = Name;
               end loop;
            end loop;
            if not Found then
               return Name;
            end if;
         end;
      end loop;
   end Unique_Name;

   function Field (Index : Positive) return String is
     (Ada.Strings.Fixed.Trim (Inputs.Get_Text (Values (Index)), Ada.Strings.Both));

   procedure Set_Field (Index : Positive; Caption, Value : String) is
   begin
      Labels.Set_Text (Captions (Index), Caption);
      Inputs.Set_Text (Values (Index), Value);
      Set_Flag (+Captions (Index), Visible, Caption'Length > 0);
      Set_Flag (+Values (Index), Visible, Caption'Length > 0);
   end Set_Field;

   procedure Prepare_Form (New_Mode : Form_Mode; Title : String) is
   begin
      Mode := New_Mode;
      Dialogs.Set_Title (Form, Title);
      for I in Values'Range loop
         Set_Field (I, "", "");
      end loop;
      Set_Flag (+Kind_Choice, Visible, New_Mode in Import_Media | Add_Track);
      Combos.Set_Selected_Index (Kind_Choice, 1);
   end Prepare_Form;

   procedure Form_Result (Dialog : Widget_Handle; Index : Natural; Caption : String) is
      pragma Unreferenced (Dialog, Caption);
   begin
      if Index /= 1 then
         Dialogs.Hide (Form);
         return;
      end if;
      case Mode is
         when Import_Media =>
            if not Valid_Path (Field (1)) then
               return;
            end if;
            Execute_Line ("import " & US.To_String (Form_Target) & " " & Field (1) &
              " " & Field (2) & " " & Combos.Get_Selected_Text (Kind_Choice));
         when Add_Track =>
            Execute_Line ("track " & US.To_String (Form_Target) & " " & Combos.Get_Selected_Text (Kind_Choice));
         when Place_Clip =>
            Execute_Line ("place " & US.To_String (Form_Target) & " " &
              Combos.Get_Selected_Text (Track_Choice) & " " & Combos.Get_Selected_Text (Source_Choice) &
              " " & Field (1) & " " & Field (2) & " " & Field (3));
         when Move_Clip =>
            Execute_Line ("move " & US.To_String (Form_Target) & " " & Field (1));
         when Project_Settings =>
            Execute_Line ("settings " & Field (1) & " " & Field (2) & " " & Field (3));
      end case;
      if Reply.Ok then
         Dialogs.Hide (Form);
      else
         Dialogs.Set_Title (Form, FS.Image (Reply));
      end if;
   end Form_Result;

   procedure Import_Selected (Files : Adi.OS.String_Array) is
   begin
      if Files'Length = 0 then
         return;
      end if;
      if not Valid_Path (US.To_String (Files (Files'First))) then
         return;
      end if;
      Form_Target := US.To_Unbounded_String (Unique_Name ("media"));
      Prepare_Form (Import_Media, "Import Files - enter media duration in seconds");
      Set_Field (1, "Media file", US.To_String (Files (Files'First)));
      Set_Field (2, "Duration (seconds)", "");
      Dialogs.Show (Form);
   end Import_Selected;

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
         if not Valid_Path (Path) then
            return;
         end if;
         Execute_Line ("save " & Path);
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
         Adi.OS.Show_Save_File_Dialog (Save_Selected'Unrestricted_Access, W,
           Default_Location => (if US.Length (Project_Path) = 0 then "project.fw" else US.To_String (Project_Path)));
      else
         Execute_Line ("save " & US.To_String (Project_Path));
         if Reply.Ok then
            Saved_History := History;
            Update_Title;
            Tell ("Project saved.");
         end if;
      end if;
   end Save_Project;

   procedure Reset_View is
      V : Timeline_View.Views.Ref := Timeline_View.Views.Borrow (Tracks);
   begin
      V.Selected_Clip := US.Null_Unbounded_String;
      V.Playhead := 0;
      V.First_Second := 0.0;
      V.Razor_Mode := False;
      Set_Selected (+Razor_Button, False);
      Timeline_View.Set_Razor_Pointer (V.Ptr.all, 0.0, 0.0, False);
      V.Drag_Active := False;
      V.Scrubbing := False;
      Labels.Set_Text (Tool_Status, "Select: drag clips or their edges to edit");
   end Reset_View;

   procedure Open_Selected (Files : Adi.OS.String_Array) is
   begin
      if Files'Length = 0 then
         return;
      end if;
      if not Valid_Path (US.To_String (Files (Files'First))) then
         return;
      end if;
      Execute_Line ("load " & US.To_String (Files (Files'First)));
      --  Load can fail after replaying part of a file; retain the dirty marker.
      if Reply.Ok then
         Project_Path := Files (Files'First);
         Saved_History := History;
         Reset_View;
         Refresh_Timeline;
         Tell ("Project opened.");
      end if;
   end Open_Selected;

   procedure Continue_Action is
      Action : constant Pending_Action := Pending;
   begin
      Pending := Nothing;
      case Action is
         when New_Project =>
            while FS.History_Length (Editor) > 0 loop
               FS.Execute (Editor, "undo", Reply);
               exit when not Reply.Ok;
            end loop;
            Project_Path := US.Null_Unbounded_String;
            Saved_History := History;
            Reset_View;
            Refresh_Timeline;
            Tell ("New project. Import files and add a track to begin.");
         when Open_Project =>
            Adi.OS.Show_Open_File_Dialog (Open_Selected'Unrestricted_Access, W,
              Filters => [(US.To_Unbounded_String ("Framewise projects"), US.To_Unbounded_String ("fw"))]);
         when Close_Editor =>
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
      if Dirty and then not Allow_Close then
         Allow := False;
         Request_Action (Close_Editor);
      end if;
   end Close_Requested;

   procedure Export_Selected (Files : Adi.OS.String_Array) is
   begin
      if Files'Length > 0 and then Valid_Path (US.To_String (Files (Files'First))) then
         Execute_Line ("export " & US.To_String (Files (Files'First)));
         if Reply.Ok then
            Tell ("Video exported.");
         end if;
      end if;
   end Export_Selected;

   procedure Clip_Selected (Name : String) is
   begin
      Set_Focus (W, +Tracks);
      Tell ((if Name'Length = 0 then "No clip selected."
             else "Selected: " & Name & ". Drag to move, drag an edge to trim, or use Move / Delete."));
   end Clip_Selected;

   procedure Delete_Selected is
      Name : US.Unbounded_String;
   begin
      declare
         V : Timeline_View.Views.Ref := Timeline_View.Views.Borrow (Tracks);
      begin
         Name := V.Selected_Clip;
      end;
      if US.Length (Name) = 0 then
         Tell ("Select a timeline clip first.");
         return;
      end if;
      Execute_Line ("delete " & US.To_String (Name));
   end Delete_Selected;

   procedure Clicked (Button : Widget_Handle) is
   begin
      if Button = Widget_Handle'(+File_Button) then
         declare
            G : constant Rectangle := Get_Geometry (Button);
         begin
            Menus.Show_At (File_Menu, G.X, G.Y + G.Height, 230.0);
         end;
      elsif Button = Widget_Handle'(+Undo_Button) then
         Execute_Line ("undo");
      elsif Button = Widget_Handle'(+Delete_Button) then
         Delete_Selected;
      elsif Button = Widget_Handle'(+Add_Track_Button) then
         Form_Target := US.To_Unbounded_String (Unique_Name ("track"));
         Prepare_Form (Add_Track, "Add Track - choose media type");
         Dialogs.Show (Form);
      elsif Button = Widget_Handle'(+Place_Button) then
         if Combos.Get_Selected_Index (Source_Choice) = 0 or else Combos.Get_Selected_Index (Track_Choice) = 0 then
            Tell ("Import a media file and add a track before adding a clip.");
            return;
         end if;
         Form_Target := US.To_Unbounded_String (Unique_Name ("clip"));
         Prepare_Form (Place_Clip, "Add selected media to selected track");
         Set_Field (1, "Source in (seconds)", "0");
         for S of FS.Sequence_Of (Editor).Sources loop
            if S.Used and then Framewise.Image (S.N) = Combos.Get_Selected_Text (Source_Choice) then
               Set_Field (2, "Source out (seconds)", FS.Image_Time (S.Length));
            end if;
         end loop;
         declare
            V : Timeline_View.Views.Ref := Timeline_View.Views.Borrow (Tracks);
         begin
            Set_Field (3, "Timeline start (seconds)", FS.Image_Time (V.Playhead));
         end;
         Dialogs.Show (Form);
      elsif Button = Widget_Handle'(+Move_Button) then
         declare
            V : Timeline_View.Views.Ref := Timeline_View.Views.Borrow (Tracks);
         begin
            Form_Target := V.Selected_Clip;
         end;
         for T of FS.Sequence_Of (Editor).Tracks loop
            for I in 1 .. T.Count loop
               if T.Used and then Framewise.Image (T.Clips (I).N) = US.To_String (Form_Target) then
                  Prepare_Form (Move_Clip, "Move selected clip");
                  Set_Field (1, "Timeline start (seconds)", FS.Image_Time (T.Clips (I).Start));
                  Dialogs.Show (Form);
                  return;
               end if;
            end loop;
         end loop;
         Tell ("Select a timeline clip first.");
      else
         declare
            V : Timeline_View.Views.Ref := Timeline_View.Views.Borrow (Tracks);
         begin
            if Button = Widget_Handle'(+Razor_Button) then
               V.Razor_Mode := not V.Razor_Mode;
               Set_Selected (+Razor_Button, V.Razor_Mode);
               Mark_Dirty (+Tracks);
               Labels.Set_Text (Tool_Status,
                 (if V.Razor_Mode then "Razor: click inside a clip to split"
                  else "Select: drag clips or their edges to edit"));
            elsif Button = Widget_Handle'(+Zoom_In) then
               V.Zoom := Long_Float'Min (256.0, V.Zoom * 2.0);
            elsif Button = Widget_Handle'(+Zoom_Out) then
               V.Zoom := Long_Float'Max (8.0, V.Zoom / 2.0);
            elsif Button = Widget_Handle'(+Scroll_Left) then
               V.First_Second := Long_Float'Max (0.0, V.First_Second - 5.0);
            elsif Button = Widget_Handle'(+Scroll_Right) then
               V.First_Second := Long_Float'Min
                 (Framewise.Seconds (Framewise.Time'Last / 2), V.First_Second + 5.0);
            elsif Button = Widget_Handle'(+Start_Button) then
               V.Playhead := 0;
               V.First_Second := 0.0;
               Show_Preview (Timeline_View.Preview_Text (FS.Sequence_Of (Editor), V.Playhead));
            end if;
            Mark_Dirty (+Tracks);
         end;
      end if;
   end Clicked;

   procedure Menu_Selected (Menu : Menus.Menu_Handle; Index : Positive; Text : String) is
      pragma Unreferenced (Menu, Text);
   begin
      case Index is
         when 1 => Request_Action (New_Project);
         when 2 => Request_Action (Open_Project);
         when 3 => Save_Project;
         when 4 => Save_Project (True);
         when 5 => Adi.OS.Show_Open_File_Dialog (Import_Selected'Unrestricted_Access, W);
         when 6 =>
            Prepare_Form (Project_Settings, "Project Settings");
            Set_Field (1, "Width (pixels)", FS.Settings_Of (Editor).Width'Image);
            Set_Field (2, "Height (pixels)", FS.Settings_Of (Editor).Height'Image);
            Set_Field (3, "Frames per second", FS.Settings_Of (Editor).FPS'Image);
            Dialogs.Show (Form);
         when 7 => Adi.OS.Show_Save_File_Dialog
           (Export_Selected'Unrestricted_Access, W, Default_Location => "out.mp4");
         when 8 => Request_Action (Close_Editor);
         when others => null;
      end case;
   end Menu_Selected;

   procedure Key_Down
     (Scancode : Adi.SDL.Events.SDL_Scancode;
      Keycode : Adi.SDL.Events.SDL_Keycode;
      Key_Mod : Adi.SDL.Events.SDL_Keymod;
      Repeat : Boolean; Handled : in out Boolean)
   is
      pragma Unreferenced (Keycode);
      use type Adi.SDL.Events.SDL_Keymod;
      Ctrl : constant Boolean := (Key_Mod and Adi.SDL.Events.SDL_KMOD_CTRL) /= 0;
   begin
      if Repeat or else Dialogs.Is_Shown (Form) or else Dialogs.Is_Shown (Confirm) then
         return;
      end if;
      if Ctrl and then Scancode = Key_S then
         Save_Project ((Key_Mod and Adi.SDL.Events.SDL_KMOD_SHIFT) /= 0);
      elsif Ctrl and then Scancode = Key_O then
         Request_Action (Open_Project);
      elsif Ctrl and then Scancode = Key_N then
         Request_Action (New_Project);
      elsif Ctrl and then Scancode = Adi.SDL.Events.SDL_SCANCODE_Z then
         Execute_Line ("undo");
      elsif Scancode = Adi.SDL.Events.SDL_SCANCODE_DELETE and then Get_Focus_Handle (W) = Widget_Handle'(+Tracks) then
         Delete_Selected;
      else
         return;
      end if;
      Handled := True;
   end Key_Down;

   function Make_Label (Parent : Widget_Handle; Text : String) return Labels.Label_Handle is
      H : constant Labels.Label_Handle := Labels.Create_Handle (Text);
   begin
      Set_Part_Style (+H, Label_Part, Style.Base (Text_Style).Build);
      Add_Child (Parent, +H);
      return H;
   end Make_Label;

   function Make_Button (Parent : Widget_Handle; Text : String) return Buttons.Button_Handle is
      H : constant Buttons.Button_Handle := Buttons.Create_Handle (Text);
   begin
      Style_Button (H);
      Buttons.Connect_Clicked (H, Clicked'Unrestricted_Access);
      Add_Child (Parent, +H);
      return H;
   end Make_Button;

   procedure Add_Label (Parent : Widget_Handle; Text : String) is
      H : constant Labels.Label_Handle := Make_Label (Parent, Text);
      pragma Unreferenced (H);
   begin
      null;
   end Add_Label;

begin
   A.Init;
   Adi.Layout_Util.Set_Px_Maps_To_Dip (True);
   A.Set_Target_FPS (60);
   W := Create_Window_Handle ("Framewise", Adi.Window.Extent (Px (1280.0), Px (850.0)));
   declare
      Root, Menu_Row, Bin, Monitor, Lower, Timeline_Tools,
        Placement_Row, Track_Scroll : Boxes.Box_Handle;
      Workspace, Main_Split : Editor_Split.Views.Handle;
      package Mouse renames Adi.SDL.Mouse;
      use type Mouse.SDL_SystemCursor;
      use type Mouse.SDL_Cursor_Access;
      use type Adi.SDL.Video.SDL_Window_Ptr;
      type Cursor_Array is array (Mouse.SDL_SystemCursor) of Mouse.SDL_Cursor_Access;
      Cursors : Cursor_Array := [others => null];

      --  Poll each frame so changes of tool, overlays and drag state are
      --  reflected even if the pointer remains still. Cache native resources.
      procedure Update_Cursor (Win : Window_Handle) is
         X, Y : aliased Float;
         Ignored : Mouse.SDL_MouseButtonFlags;
         Kind : Mouse.SDL_SystemCursor := Mouse.SDL_SYSTEM_CURSOR_DEFAULT;
         type Handles is array (Positive range <>) of Widget_Handle;
      begin
         if Mouse.SDL_GetMouseFocus /= Get_SDL_Window (Win) then
            declare
               T : Timeline_View.Views.Ref := Timeline_View.Views.Borrow (Tracks);
            begin
               Timeline_View.Set_Razor_Pointer (T.Ptr.all, 0.0, 0.0, False);
            end;
            return;
         end if;
         Ignored := Mouse.SDL_GetMouseState (X'Access, Y'Access);
         declare
            T : Timeline_View.Views.Ref := Timeline_View.Views.Borrow (Tracks);
            M : Editor_Split.Views.Ref := Editor_Split.Views.Borrow (Main_Split);
            V : Editor_Split.Views.Ref := Editor_Split.Views.Borrow (Workspace);
         begin
            Timeline_View.Set_Razor_Pointer (T.Ptr.all, Pixel_Type (X), Pixel_Type (Y),
              Overlay_Count (Win) = 0 and then Has_State (+Tracks, State_Hovered));
            if Overlay_Count (Win) = 0 then
               if T.Drag_Active or T.Scrubbing then
                  Kind := Timeline_View.Cursor_At (T.Ptr.all, Pixel_Type (X), Pixel_Type (Y));
               elsif M.Dragging or else Has_State (+Main_Split, State_Hovered) then
                  Kind := Editor_Split.Cursor_At (M.Ptr.all, Pixel_Type (X), Pixel_Type (Y));
               end if;
               if Kind = Mouse.SDL_SYSTEM_CURSOR_DEFAULT and then
                 (V.Dragging or else Has_State (+Workspace, State_Hovered))
               then
                  Kind := Editor_Split.Cursor_At (V.Ptr.all, Pixel_Type (X), Pixel_Type (Y));
               end if;
               if Kind = Mouse.SDL_SYSTEM_CURSOR_DEFAULT and then Has_State (+Tracks, State_Hovered) then
                  Kind := Timeline_View.Cursor_At (T.Ptr.all, Pixel_Type (X), Pixel_Type (Y));
               end if;
            end if;
         end;
         if Kind = Mouse.SDL_SYSTEM_CURSOR_DEFAULT then
            declare
               Controls : constant Handles := [+File_Button, +Add_Track_Button, +Place_Button,
                 +Undo_Button, +Delete_Button, +Razor_Button, +Move_Button,
                 +Zoom_In, +Zoom_Out, +Scroll_Left, +Scroll_Right, +Start_Button,
                 +Source_Choice, +Track_Choice, +Kind_Choice,
                 +Dialogs.Get_Button_Handle (Form, 1), +Dialogs.Get_Button_Handle (Form, 2),
                 +Dialogs.Get_Button_Handle (Confirm, 1), +Dialogs.Get_Button_Handle (Confirm, 2)];
            begin
               for H of Controls loop
                  if Has_State (H, State_Hovered) then
                     Kind := Mouse.SDL_SYSTEM_CURSOR_POINTER;
                     exit;
                  end if;
               end loop;
               for H of Values loop
                  if Has_State (+H, State_Hovered) then
                     Kind := Mouse.SDL_SYSTEM_CURSOR_TEXT;
                     exit;
                  end if;
               end loop;
            end;
         end if;
         if Cursors (Kind) = null then
            Cursors (Kind) := Mouse.SDL_CreateSystemCursor (Kind);
         end if;
         if Cursors (Kind) /= null then
            declare
               Applied : constant Adi.SDL.C_bool := Mouse.SDL_SetCursor (Cursors (Kind));
               pragma Unreferenced (Applied);
            begin
               null;
            end;
         end if;
      end Update_Cursor;

   begin
      Root := Boxes.Create_Handle;
      Menu_Row := Boxes.Create_Handle;
      Lower := Boxes.Create_Handle;
      Bin := Boxes.Create_Handle;
      Monitor := Boxes.Create_Handle;
      Timeline_Tools := Boxes.Create_Handle;
      Placement_Row := Boxes.Create_Handle;
      Track_Scroll := Boxes.Create_Handle;
      Workspace := Editor_Split.Views.New_Widget;
      Main_Split := Editor_Split.Views.New_Widget;
      Set_Part_Style (+Lower, Main_Part, Style.Base
        ((Panel_Style with delta Overflow_Y => Set (Overflow_Auto))).Build);
      Set_Part_Style (+Root, Main_Part, Style.Base (Panel_Style).Build);
      declare
         Rows : constant Box_Array := [Menu_Row, Timeline_Tools, Placement_Row];
      begin
         for H of Rows loop
            Set_Part_Style (+H, Main_Part, Style.Base
              ((Row_Style with delta Flex_Wrap => Set (Wrap))).Build);
         end loop;
      end;
      Set_Part_Style (+Workspace, Main_Part, Style.Base
        ((Row_Style with delta Flex_Grow => Set (1.0))).Build);
      Set_Part_Style (+Bin, Main_Part, Style.Base
        ((Panel_Style with delta Overflow_Y => Set (Overflow_Auto))).Build);
      Set_Part_Style (+Monitor, Main_Part, Style.Base
        ((Panel_Style with delta Flex_Grow => Set (1.0), Overflow_Y => Set (Overflow_Auto))).Build);
      File_Button := Make_Button (+Menu_Row, "File");
      Add_Label (+Bin, "Project Files");
      Sources := Adi.Widget.Text_Editor.Create_Handle ("");
      Adi.Widget.Text_Editor.Set_Read_Only (Sources);
      Set_Part_Style (+Sources, Main_Part, Style.Base
        ((Flex_Grow => Set (1.0), Height => Set (Size (Px (0.0))), Min_Height => Set (Size (Px (40.0))),
          Background_Color => Set_Bg (RGB (20, 26, 36)), others => <>)).Build);
      Set_Part_Style (+Sources, Text_Part, Style.Base (Text_Style).Build);
      Add_Child (+Bin, +Sources);
      Add_Label (+Bin, "Selected media");
      Source_Choice := Combos.Create_Handle;
      Style_Combo (Source_Choice);
      Add_Child (+Bin, +Source_Choice);
      Add_Label (+Monitor, "Video Preview");
      Preview := Make_Label (+Monitor, "");
      Set_Part_Style (+Preview, Main_Part, Style.Base
        ((Flex_Grow => Set (1.0), Height => Set (Size (Px (0.0))), Min_Height => Set (Size (Px (40.0))),
          Padding => Set (CSS_Box (Px (24.0))),
          Background_Color => Set_Bg (RGB (0, 0, 0)), others => <>)).Build);
      Start_Button := Make_Button (+Monitor, "Go to Start");
      Set_Part_Style (+Start_Button, Main_Part, Style.Base
        ((Width => Set (Size (Px (130.0))),
          Background_Color => Set_Bg (RGB (38, 50, 67)),
          Padding => Set (CSS_Box (Px (7.0), Px (10.0))), others => <>)).Build);
      Add_Label (+Monitor, "Drag the timeline ruler to scrub. Playback is not available yet.");
      Add_Child (+Workspace, +Bin);
      Add_Child (+Workspace, +Monitor);
      Add_Track_Button := Make_Button (+Timeline_Tools, "Add Track");
      Undo_Button := Make_Button (+Timeline_Tools, "Undo");
      Razor_Button := Make_Button (+Timeline_Tools, "Razor");
      Set_Part_Style (+Razor_Button, Main_Part, Style.Base
        ((Background_Color => Set_Bg (RGB (38, 50, 67)),
          Padding => Set (CSS_Box (Px (7.0), Px (10.0))),
          Border_Radius => Set (Radius (Px (3.0))), others => <>))
        .On_Selected ((Background_Color => Set_Bg (RGB (52, 112, 204)), others => <>)).Build);
      Move_Button := Make_Button (+Timeline_Tools, "Move Clip");
      Delete_Button := Make_Button (+Timeline_Tools, "Delete Clip");
      Zoom_Out := Make_Button (+Timeline_Tools, "Zoom -");
      Zoom_In := Make_Button (+Timeline_Tools, "Zoom +");
      Scroll_Left := Make_Button (+Timeline_Tools, "Earlier");
      Scroll_Right := Make_Button (+Timeline_Tools, "Later");
      Add_Label (+Placement_Row, "Target track");
      Track_Choice := Combos.Create_Handle;
      Style_Combo (Track_Choice);
      Add_Child (+Placement_Row, +Track_Choice);
      Place_Button := Make_Button (+Placement_Row, "Add Selected Media to Track");
      Tool_Status := Make_Label (+Placement_Row, "Select: drag clips or their edges to edit");
      Tracks := Timeline_View.Views.New_Widget;
      Set_Flag (+Tracks, Clickable, True);
      Set_Flag (+Tracks, Focusable, True);
      declare
         V : Timeline_View.Views.Ref := Timeline_View.Views.Borrow (Tracks);
      begin
         V.Read_Sequence := Read_Sequence'Unrestricted_Access;
         V.Submit_Command := Execute_Line'Unrestricted_Access;
         V.Preview_Changed := Show_Preview'Unrestricted_Access;
         V.Selection_Changed := Clip_Selected'Unrestricted_Access;
      end;
      Set_Part_Style (+Track_Scroll, Main_Part, Style.Base
        ((Flex_Grow => Set (1.0), Min_Height => Set (Size (Px (80.0))),
          Overflow_Y => Set (Overflow_Auto), others => <>)).Build);
      Set_Part_Style (+Tracks, Label_Part, Style.Base (Text_Style).Build);
      Set_Part_Style (+Tracks, Cursor_Part, Style.Base
        ((Background_Color => Set_Bg (RGB (255, 225, 130)), others => <>)).Build);
      Set_Part_Style (+Tracks, Custom_Part, Style.Base
        ((Background_Color => Set_Bg (RGB (38, 49, 65)), others => <>)).Build);
      Set_Part_Style (+Tracks, Indicator_Part, Style.Base
        ((Background_Color => Set_Bg (RGB (46, 104, 173)), others => <>)).Build);
      Set_Part_Style (+Tracks, Selected_Part, Style.Base
        ((Background_Color => Set_Bg (RGB (176, 119, 37)), others => <>)).Build);
      Add_Child (+Track_Scroll, +Tracks);
      declare
         Sections : constant Box_Array := [Timeline_Tools, Placement_Row, Track_Scroll];
      begin
         for H of Sections loop
            Add_Child (+Lower, +H);
         end loop;
      end;
      Add_Child (+Main_Split, +Workspace);
      Add_Child (+Main_Split, +Lower);
      declare
         V : Editor_Split.Views.Ref := Editor_Split.Views.Borrow (Workspace);
         M : Editor_Split.Views.Ref := Editor_Split.Views.Borrow (Main_Split);
      begin
         V.First := +Bin;
         V.Second := +Monitor;
         V.Fraction := 0.31;
         V.Minimum_First := 240.0;
         V.Minimum_Second := 300.0;
         M.First := +Workspace;
         M.Second := +Lower;
         M.Vertical := True;
         M.Fraction := 0.56;
         M.Minimum_First := 180.0;
         M.Minimum_Second := 220.0;
      end;
      Set_Part_Style (+Main_Split, Main_Part, Style.Base
        ((Flex_Grow => Set (1.0), Height => Set (Size (Px (0.0))), others => <>)).Build);
      Set_Flag (+Workspace, Clickable, True);
      Set_Flag (+Main_Split, Clickable, True);
      Set_Part_Style (+Workspace, Indicator_Part, Style.Base
        ((Background_Color => Set_Bg (RGB (8, 33, 71)), others => <>)).Build);
      Set_Part_Style (+Main_Split, Indicator_Part, Style.Base
        ((Background_Color => Set_Bg (RGB (8, 33, 71)), others => <>)).Build);
      Add_Child (+Root, +Menu_Row);
      Add_Child (+Root, +Main_Split);
      Status := Make_Label (+Root, "Ready. Import files and add a track, or open a .fw project.");

      Form := Dialogs.Create_Handle;
      Form_Content := Boxes.Create_Handle;
      Set_Part_Style (+Form_Content, Main_Part, Style.Base (Panel_Style).Build);
      for I in Values'Range loop
         Captions (I) := Make_Label (+Form_Content, "");
         Values (I) := Inputs.Create_Handle ("");
         Inputs.Set_Min_Visible_Chars (Values (I), 40);
         Set_Part_Style (+Values (I), Text_Part, Style.Base (Text_Style).Build);
         Set_Part_Style (+Values (I), Main_Part, Style.Base
           ((Background_Color => Set_Bg (RGB (38, 50, 67)),
             Padding => Set (CSS_Box (Px (6.0))), others => <>)).Build);
         Add_Child (+Form_Content, +Values (I));
      end loop;
      Kind_Choice := Combos.Create_Handle;
      Style_Combo (Kind_Choice);
      Combos.Add_Item (Kind_Choice, "video");
      Combos.Add_Item (Kind_Choice, "audio");
      Combos.Add_Item (Kind_Choice, "both");
      Add_Child (+Form_Content, +Kind_Choice);
      Dialogs.Set_Content (Form, +Form_Content);
      Dialogs.Set_Auto_Close (Form, False);
      Dialogs.Add_Button (Form, "Apply");
      Dialogs.Add_Button (Form, "Cancel");
      Dialogs.Connect_Result (Form, Form_Result'Unrestricted_Access);
      Confirm := Dialogs.Create_Handle;
      Dialogs.Set_Title (Confirm, "Unsaved project changes");
      Dialogs.Set_Message (Confirm, "Discard changes? Choose Cancel to return and save your project first.");
      Dialogs.Add_Button (Confirm, "Discard Changes");
      Dialogs.Add_Button (Confirm, "Cancel");
      Dialogs.Set_Default_Button (Confirm, 2);
      Dialogs.Connect_Result (Confirm, Confirm_Result'Unrestricted_Access);
      declare
         All_Dialogs : constant Dialog_Array := [Form, Confirm];
      begin
         for D of All_Dialogs loop
            Dialogs.Attach_Window (D, W);
            Dialogs.Set_Panel_Style (D,
              (Main_Part => (Style => Style.Base (Panel_Style).Build, Enabled => True), others => <>));
            Dialogs.Set_Button_Row_Style (D,
              (Main_Part => (Style => Style.Base (Row_Style).Build, Enabled => True), others => <>));
            Dialogs.Set_Title_Style (D,
              (Label_Part => (Style => Style.Base (Text_Style).Build, Enabled => True), others => <>));
            Dialogs.Set_Message_Style (D,
              (Label_Part => (Style => Style.Base (Text_Style).Build, Enabled => True), others => <>));
            Style_Button (Dialogs.Get_Button_Handle (D, 1));
            Style_Button (Dialogs.Get_Button_Handle (D, 2));
         end loop;
      end;
      File_Menu := Menus.Create_Handle;
      Menus.Attach_Window (File_Menu, W);
      Menus.Set_Menu_Part_Styles (File_Menu,
        (Main_Part => (Style => Style.Base (Panel_Style).Build, Enabled => True), others => <>));
      Menus.Set_Item_Part_Styles (File_Menu,
        (Main_Part =>
           (Style => Style.Base
              ((Padding => Set (CSS_Box (Px (6.0), Px (8.0))), others => <>))
              .On_Hover
                ((Background_Color => Set_Bg (RGB (45, 78, 119)), others => <>))
              .On_Selected
                ((Background_Color => Set_Bg (RGB (45, 78, 119)), others => <>)).Build,
            Enabled => True),
         Label_Part => (Style => Style.Base (Text_Style).Build, Enabled => True),
         others => <>));
      Menus.Add_Item (File_Menu, "New Project     Ctrl+N");
      Menus.Add_Item (File_Menu, "Open Project    Ctrl+O");
      Menus.Add_Item (File_Menu, "Save            Ctrl+S");
      Menus.Add_Item (File_Menu, "Save As   Ctrl+Shift+S");
      Menus.Add_Item (File_Menu, "Import Files...");
      Menus.Add_Item (File_Menu, "Project Settings...");
      Menus.Add_Item (File_Menu, "Export Video...");
      Menus.Add_Item (File_Menu, "Exit");
      Menus.Connect_Item_Selected (File_Menu, Menu_Selected'Unrestricted_Access);
      Connect_Key_Down (W, Key_Down'Unrestricted_Access);
      Connect_Close_Request (W, Close_Requested'Unrestricted_Access);
      Set_Root (W, +Root);
      A.Add_Window (W);
      Refresh_Timeline;
      Set_Focus (W, +Tracks);
      Connect_Frame (W, Update_Cursor'Unrestricted_Access);
      A.Run;
      declare
         Restored : constant Adi.SDL.C_bool := Mouse.SDL_SetCursor (Mouse.SDL_GetDefaultCursor);
         pragma Unreferenced (Restored);
      begin
         for C of Cursors loop
            if C /= null then
               Mouse.SDL_DestroyCursor (C);
            end if;
         end loop;
      end;
      Menus.Destroy (File_Menu);
      Adi.Window.Destroy (W);
   end;
end Framewise_UI;
