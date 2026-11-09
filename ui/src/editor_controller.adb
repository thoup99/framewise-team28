with Adi.Core; use Adi.Core;
with Adi.CSS_Styles; use Adi.CSS_Styles;
with Adi.Widget; use Adi.Widget;
with Adi.Widget_Styles; use Adi.Widget_Styles;
with Adi.Window; use Adi.Window;
with Framewise;
with Timeline_View;
with Adi.Widget.Text_Editor;
with Adi.SDL.Events;
with Editor_Context; use Editor_Context;
with Adi.OS;
with Adi.App;
with Editor_Styles; use Editor_Styles;
with Ada.Characters.Latin_1;
with Ada.Characters.Handling;
with Editor_Console;
with Editor_Export;
with Ada.Directories;
with Ada.Strings.Fixed;
with Interfaces.C.Extensions;
with Interfaces.C.Strings;
with Adi.SDL.Video;
with Editor_Dialogs; use Editor_Dialogs;

package body Editor_Controller is
   use type Buttons.Button_Handle;
   use type Labels.Label_Handle;
   use type Inputs.Text_Input_Handle;
   use type Combos.Combo_Box_Handle;
   use type Adi.Widget.Text_Editor.Text_Editor_Handle;
   use type Timeline_View.Views.Handle;
   use type Adi.SDL.Events.SDL_Scancode;
   use type US.Unbounded_String;
   use type Framewise.Time;
   use type Boxes.Box_Handle;

   Key_N : constant Adi.SDL.Events.SDL_Scancode := 17;
   Key_O : constant Adi.SDL.Events.SDL_Scancode := 18;
   Key_S : constant Adi.SDL.Events.SDL_Scancode := 22;

   --  The pinned toolkit exposes the SDL window but has no title setter.
   function Set_Window_Title
     (Window : Adi.SDL.Video.SDL_Window_Ptr;
      Title : Interfaces.C.Strings.chars_ptr) return Interfaces.C.Extensions.bool
     with Import, Convention => C, External_Name => "SDL_SetWindowTitle";

   function Matches_Filter (Kind : FS.Media_Kind) return Boolean is
     (case Current_Filter is
         when All_Media => True,
         when Video_Media => Kind'Image in "VIDEO" | "BOTH",
         when Audio_Media => Kind'Image in "AUDIO" | "BOTH");

   procedure Update_Filter_Buttons is
   begin
      for F in Media_Filter loop
         Set_Selected (+Filter_Buttons (F), F = Current_Filter);
      end loop;
   end Update_Filter_Buttons;

   procedure Tell (Text : String) is
   begin
      Labels.Set_Text (Status, Text);
   end Tell;

   procedure Report_Editor_Error (Action, Message : String) is
   begin
      Tell (Message);
      Editor_Console.Record_Command (Action, "err " & Message, Editor_Console.Editor_Action);
   end Report_Editor_Error;

   procedure Snap_Interval_Changed (Input : Widget_Handle; Text : String) is
      pragma Unreferenced (Input);
      Interval : Framewise.Time := 0;
      Valid : Boolean;
   begin
      declare
         Seconds : Long_Float;
      begin
         Seconds := Long_Float'Value (Text);
         if Seconds in 1.0 / Long_Float (Framewise.Timebase) ..
           Framewise.Seconds (Framewise.Time'Last / 2)
         then
            Interval := Framewise.Time (Seconds * Long_Float (Framewise.Timebase));
         end if;
      exception
         when Constraint_Error => null;
      end;
      Valid := Interval in 1 .. Framewise.Time'Last / 2;
      if Valid then
         declare
            V : Timeline_View.Views.Ref := Timeline_View.Views.Borrow (Tracks);
         begin
            V.Snap_Interval := Interval;
            Mark_Dirty (+Tracks);
         end;
         Tell ("Control-drag snap interval: " & FS.Image_Time (Interval) & " s.");
      else
         Tell ("Enter positive snap seconds (minimum 1/90000 s); the last valid interval is still active.");
      end if;
      declare
         Text_Color : constant Color_Value :=
           (if Valid then RGB (215, 225, 239) else RGB (255, 150, 150));
      begin
         Set_Part_Style (+Snap_Interval_Input, Text_Part, Style.Base
           ((Text_Style with delta Color => Set (Text_Color))).Build);
      end;
   end Snap_Interval_Changed;

   function History return US.Unbounded_String is
      Result : US.Unbounded_String;
   begin
      for I in 1 .. FS.History_Length (Editor) loop
         US.Append (Result, FS.History_Line (Editor, I) & Ada.Characters.Latin_1.LF);
      end loop;
      return Result;
   end History;

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

   function Read_Sequence return FS.Sequence_View is (FS.Sequence_Of (Editor));

   procedure Cursor_Time_Changed (Input : Widget_Handle; Text : String) is
      pragma Unreferenced (Input);
      Value : Long_Float;
      Valid : Boolean := False;
   begin
      if Get_Focus_Handle (W) /= Widget_Handle'(+Cursor_Time_Input) then
         return;
      end if;
      begin
         Value := Long_Float'Value (Text);
         Valid := Value in 0.0 .. Framewise.Seconds (Framewise.Time'Last / 2);
      exception
         when Constraint_Error => null;
      end;
      Set_Part_Style (+Cursor_Time_Input, Main_Part, Style.Base
        ((Width => Set (Size (Px (110.0))), Flex_Shrink => Set (0.0),
          Background_Color => Set_Bg ((if Valid then RGB (38, 50, 67) else RGB (91, 39, 45))),
          Padding => Set (CSS_Box (Px (6.0))), others => <>)).Build);
      if Valid then
         declare
            V : Timeline_View.Views.Ref := Timeline_View.Views.Borrow (Tracks);
            Span : constant Long_Float := Long_Float'Max
              (1.0, Long_Float (Get_Geometry (+Tracks).Width - 110.0) / V.Zoom);
         begin
            V.Playhead := Framewise.Time (Value * Long_Float (Framewise.Timebase));
            if Value < V.First_Second or else Value > V.First_Second + Span then
               V.First_Second := Long_Float'Max (0.0, Value - Span / 2.0);
            end if;
            Show_Preview (Timeline_View.Preview_Text (Read_Sequence, V.Playhead));
            Mark_Dirty (+Tracks);
         end;
      end if;
   end Cursor_Time_Changed;

   procedure Show_Preview (Text : String) is
   begin
      if Get_Focus_Handle (W) /= Widget_Handle'(+Cursor_Time_Input) then
         declare
            V : Timeline_View.Views.Ref := Timeline_View.Views.Borrow (Tracks);
         begin
            Inputs.Set_Text (Cursor_Time_Input, FS.Image_Time (V.Playhead));
         end;
      end if;
      Labels.Set_Text (Preview, Text & Ada.Characters.Latin_1.LF &
        "Video frame preview is not available yet.");
   end Show_Preview;

   --  Rebuild visible choices from the session after every successful edit.
   --  Preserve selections by name because their indices can change with filters.
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
         if Source.Used and then Matches_Filter (Source.Kind) then
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
        (if US.Length (Text) = 0 then
           (case Current_Filter is
               when All_Media => "No project files. Use Import Files to add media.",
               when Video_Media => "No video files in this project.",
               when Audio_Media => "No audio files in this project.")
         else US.To_String (Text)));
      declare
         V : Timeline_View.Views.Ref := Timeline_View.Views.Borrow (Tracks);
      begin
         Show_Preview (Timeline_View.Preview_Text (Seq, V.Playhead));
      end;
      Set_Part_Style (+Tracks, Main_Part, Style.Base
        ((Height => Set (Size (Px (Float (Natural'Max (Rows, 1) * 48 + 36)))),
          Flex_Grow => Set (1.0), Flex_Shrink => Set (0.0),
          --  Keep the clickable timeline out of its parent's scrollbar gutter.
          Margin => Set_Margin (CSS_Box (Px (0.0), Px (16.0), Px (0.0), Px (0.0))),
          Background_Color => Set_Bg (RGB (29, 38, 51)), others => <>)).Build);
      Update_Title;
      Mark_Dirty (+Tracks);
   end Refresh_Timeline;

   --  Buttons, dialogs and released timeline gestures share this boundary.
   --  Origin is explicit so console commands appear once under their own label.
   procedure Apply_Command (Line : String; Origin : Editor_Console.Command_Origin) is
   begin
      FS.Execute (Editor, Line, Reply);
      Refresh_Timeline;
      if Reply.Ok then
         Tell ("Edit applied.");
      else
         Tell (FS.Image (Reply));
      end if;
      Editor_Console.Record_Command (Line, FS.Image (Reply), Origin);
   end Apply_Command;

   procedure Execute_Line (Line : String) is
   begin
      Apply_Command (Line, Editor_Console.Editor_Action);
   end Execute_Line;

   function Safe_Path (Text : String) return Boolean is
     (Text'Length > 0 and then Text'Length <= 240 and then
      (for all C of Text => C in 'a' .. 'z' | 'A' .. 'Z' | '0' .. '9' |
        '/' | '\' | ':' | '.' | '_' | '-' | ' '));

   function Valid_Path (Text, Action : String) return Boolean is
   begin
      if Safe_Path (Text) then
         return True;
      end if;
      Report_Editor_Error (Action,
        "Choose a path using letters, numbers, spaces, dots, dashes or underscores.");
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

   procedure Reset_View is
      V : Timeline_View.Views.Ref := Timeline_View.Views.Borrow (Tracks);
   begin
      Current_Filter := All_Media;
      Update_Filter_Buttons;
      V.Selected_Clip := US.Null_Unbounded_String;
      V.Playhead := 0;
      V.First_Second := 0.0;
      V.Razor_Mode := False;
      Set_Selected (+Razor_Button, False);
      Timeline_View.Set_Razor_Pointer (V.Ptr.all, 0.0, 0.0, False);
      V.Drag_Active := False;
      V.Scrubbing := False;
      Labels.Set_Text (Tool_Status, "");
      Set_Visible (+Tool_Status, False);
   end Reset_View;

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
         Reset_View;
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
      Apply_Command (Line, Editor_Console.Console_Command);
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
               Reset_View;
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
            while FS.History_Length (Editor) > 0 loop
               FS.Execute (Editor, "undo", Reply);
               exit when not Reply.Ok;
            end loop;
            Project_Path := US.Null_Unbounded_String;
            Saved_History := History;
            Reset_View;
            Refresh_Timeline;
            Tell ("New project. Import files and add a track to begin.");
            Editor_Console.Record_Command
              ("New Project", "ok new project", Editor_Console.Editor_Action);
         when Open_Project =>
            Adi.OS.Show_Open_File_Dialog (Open_Selected'Access, W,
              Filters => [(US.To_Unbounded_String ("Framewise projects"), US.To_Unbounded_String ("fw"))]);
         when Close_Editor =>
            Allow_Close := True;
            Adi.App.Request_Quit;
         when Nothing => null;
      end case;
   end Continue_Action;

   --  Defer destructive project actions until the unsaved-change dialog resolves.
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
         Report_Editor_Error ("Delete Clip", "Select a timeline clip first.");
         return;
      end if;
      Execute_Line ("delete " & US.To_String (Name));
   end Delete_Selected;

   procedure Clicked (Button : Widget_Handle) is
   begin
      for F in Media_Filter loop
         if Button = Widget_Handle'(+Filter_Buttons (F)) then
            Current_Filter := F;
            Update_Filter_Buttons;
            Refresh_Timeline;
            return;
         end if;
      end loop;
      if Button = Widget_Handle'(+Console_Button) then
         Editor_Console.Show;
      elsif Button = Widget_Handle'(+File_Button) then
         declare
            G : constant Rectangle := Get_Geometry (Button);
         begin
            Reset_File_Menu;
            Menus.Show_At (File_Menu, G.X, G.Y + G.Height, 230.0);
         end;
      elsif Button = Widget_Handle'(+Undo_Button) then
         Execute_Line ("undo");
      elsif Button = Widget_Handle'(+Delete_Button) then
         Delete_Selected;
      elsif Button = Widget_Handle'(+Add_Track_Button) then
         Form_Target := US.To_Unbounded_String (Unique_Name ("track"));
         Prepare_Form (Add_Track, "Add Track - name and media type");
         Set_Field (1, "Track name (letters, numbers, underscores)", US.To_String (Form_Target));
         Dialogs.Show (Form);
         Set_Focus (W, +Values (1));
      elsif Button = Widget_Handle'(+Place_Button) then
         if Combos.Get_Selected_Index (Source_Choice) = 0 or else Combos.Get_Selected_Index (Track_Choice) = 0 then
            Report_Editor_Error ("Add Selected Media to Track",
              "Import a media file and add a track before adding a clip.");
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
         Report_Editor_Error ("Move Clip", "Select a timeline clip first.");
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
                  else ""));
               Set_Visible (+Tool_Status, V.Razor_Mode);
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
            elsif Button = Widget_Handle'(+End_Button) then
               V.Playhead := 0;
               for T of FS.Sequence_Of (Editor).Tracks loop
                  if T.Used then
                     for I in 1 .. T.Count loop
                        V.Playhead := Framewise.Time'Max (V.Playhead,
                          T.Clips (I).Start + T.Clips (I).Src_Out - T.Clips (I).Src_In);
                     end loop;
                  end if;
               end loop;
               V.First_Second := Long_Float'Max (0.0, Framewise.Seconds (V.Playhead) - 5.0);
               Show_Preview (Timeline_View.Preview_Text (FS.Sequence_Of (Editor), V.Playhead));
            end if;
            Mark_Dirty (+Tracks);
         end;
      end if;
   end Clicked;

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

   procedure Show_Clip_Menu (Widget : Widget_Handle; X, Y : Pixel_Type) is
      V : Timeline_View.Views.Ref := Timeline_View.Views.Borrow (Tracks);
      Local : constant Rectangle := Get_Geometry (Widget);
      Visible : constant Rectangle := Geometry_In_Window (Widget);
      --  Context-menu events arrive in window coordinates. Account for the
      --  timeline's scroll offset before looking up the clip under the mouse.
      Name : constant String := Timeline_View.Clip_At
        (V.Ptr.all, X + Local.X - Visible.X, Y + Local.Y - Visible.Y);
   begin
      Menus.Hide (Clip_Menu);
      Clip_Menu_Target := US.To_Unbounded_String (Name);
      if Name = "" then
         return;
      end if;
      --  Rebuilding clears a previous action's retained menu highlight.
      Menus.Clear_Items (Clip_Menu);
      Menus.Add_Item (Clip_Menu, "Snap Timeline Cursor Left");
      Menus.Add_Item (Clip_Menu, "Snap Timeline Cursor Right");
      Menus.Show_At (Clip_Menu, X, Y, 250.0);
   end Show_Clip_Menu;

   procedure Clip_Menu_Selected (Menu : Menus.Menu_Handle; Index : Positive; Text : String) is
      pragma Unreferenced (Menu, Text);
      Seq : constant FS.Sequence_View := Read_Sequence;
      V : Timeline_View.Views.Ref := Timeline_View.Views.Borrow (Tracks);
   begin
      --  Resolve the named clip again in case the document changed while the
      --  menu was open. Cursor navigation does not create an edit or log entry.
      for Track of Seq.Tracks loop
         if Track.Used then
            for I in 1 .. Track.Count loop
               declare
                  C renames Track.Clips (I);
               begin
                  if Framewise.Image (C.N) = US.To_String (Clip_Menu_Target) then
                     V.Playhead := C.Start + (if Index = 2 then C.Src_Out - C.Src_In else 0);
                     Show_Preview (Timeline_View.Preview_Text (Seq, V.Playhead));
                     Mark_Dirty (V.Ptr.all);
                     return;
                  end if;
               end;
            end loop;
         end if;
      end loop;
   end Clip_Menu_Selected;

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
      if Editor_Export.Is_Open then
         if Overlay_Count (W) = (if Editor_Console.Is_Open then 2 else 1) and then
           Scancode = Adi.SDL.Events.SDL_SCANCODE_ESCAPE
         then
            Editor_Export.Close;
            Handled := True;
         end if;
         return;
      end if;
      if Editor_Console.Is_Open then
         --  Leave nested context menus and dialogs in charge of their keys.
         if Overlay_Count (W) = 1 then
            Editor_Console.Handle_Key (Scancode, Repeat, Handled);
         end if;
         return;
      end if;
      if Overlay_Count (W) > 0 then
         return;
      end if;
      if Get_Focus_Handle (W) = Widget_Handle'(+Snap_Interval_Input) or else
        Get_Focus_Handle (W) = Widget_Handle'(+Cursor_Time_Input)
      then
         return;
      end if;
      if Repeat then
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
      elsif not Ctrl and then Get_Focus_Handle (W) = Widget_Handle'(+Tracks) then
         if Scancode = 21 then
            Clicked (+Razor_Button);
         elsif Scancode = Adi.SDL.Events.SDL_SCANCODE_HOME then
            Clicked (+Start_Button);
         elsif Scancode = Adi.SDL.Events.SDL_SCANCODE_END then
            Clicked (+End_Button);
         elsif Scancode in Adi.SDL.Events.SDL_SCANCODE_LEFT | Adi.SDL.Events.SDL_SCANCODE_RIGHT then
            declare
               V : Timeline_View.Views.Ref := Timeline_View.Views.Borrow (Tracks);
               Step : constant Framewise.Time :=
                 (if (Key_Mod and Adi.SDL.Events.SDL_KMOD_SHIFT) /= 0 then Framewise.Timebase
                  else Framewise.Time'Max (1, Framewise.Timebase / Framewise.Time (FS.Settings_Of (Editor).FPS)));
            begin
               if Scancode = Adi.SDL.Events.SDL_SCANCODE_LEFT then
                  V.Playhead := V.Playhead - Framewise.Time'Min (V.Playhead, Step);
               else
                  V.Playhead := V.Playhead + Framewise.Time'Min (Step, Framewise.Time'Last / 2 - V.Playhead);
               end if;
               Show_Preview (Timeline_View.Preview_Text (Read_Sequence, V.Playhead));
               Mark_Dirty (+Tracks);
            end;
         else
            return;
         end if;
      else
         return;
      end if;
      Handled := True;
   end Key_Down;
end Editor_Controller;
