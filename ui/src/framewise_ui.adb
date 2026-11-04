--  Framewise week 2: read-only tracks, sources and command-driven import.
--  The only Framewise dependency is Session. All edits and queries are
--  text lines submitted through Execute; the log is presentation state.
pragma Ada_2022;

with Ada.Characters.Latin_1;
with Ada.Strings;
with Ada.Strings.Fixed;
with Ada.Strings.Unbounded;

with Adi.App;
with Adi.Core;          use Adi.Core;
with Adi.CSS_Styles;    use Adi.CSS_Styles;
with Adi.Layout_Util;
with Adi.OS;
with Adi.Widget.Dialog;
with Timeline_View;
with Adi.SDL.Events;
with Adi.Widget;        use Adi.Widget;
with Adi.Widget.Box;
with Adi.Widget.Button;
with Adi.Widget.Label;
with Adi.Widget.Text_Editor;
with Adi.Widget.Text_Input;
with Adi.Widget_Styles; use Adi.Widget_Styles;
with Adi.Window;        use Adi.Window;

with Framewise;
with Framewise.Session;

procedure Framewise_UI is
   use type Framewise.Time;
   use type Adi.SDL.Events.SDL_Scancode;

   --  Make Adi2 widget conversion operators visible
   use type Adi.Widget.Box.Box_Handle;
   use type Adi.Widget.Button.Button_Handle;
   use type Adi.Widget.Label.Label_Handle;
   use type Adi.Widget.Text_Editor.Text_Editor_Handle;
   use type Adi.Widget.Text_Input.Text_Input_Handle;

   package FS renames Framewise.Session;
   package US renames Ada.Strings.Unbounded;

   A : Adi.App.App;
   W : Window_Handle;
   Editor : FS.Session;
   Reply : FS.Response;

   Command_Field : Adi.Widget.Text_Input.Text_Input_Handle;
   Output_Log    : Adi.Widget.Text_Editor.Text_Editor_Handle;
   Status        : Adi.Widget.Label.Label_Handle;
   Tracks : Timeline_View.Views.Handle;
   Sources : Adi.Widget.Text_Editor.Text_Editor_Handle;
   Import_Dialog : Adi.Widget.Dialog.Dialog_Handle;
   Zoom_In, Zoom_Out, Scroll_Left, Scroll_Right : Adi.Widget.Button.Button_Handle;
   View_Status : Adi.Widget.Label.Label_Handle;
   use type Timeline_View.Views.Handle;
   Import_Name : Adi.Widget.Text_Input.Text_Input_Handle;
   Import_File : Adi.Widget.Text_Input.Text_Input_Handle;
   Import_Length : Adi.Widget.Text_Input.Text_Input_Handle;
   Import_Kind : Adi.Widget.Text_Input.Text_Input_Handle;
   Import_Button : Adi.Widget.Button.Button_Handle;

   Max_Recent : constant := 10;
   type Recent_Array is array (Positive range 1 .. Max_Recent) of US.Unbounded_String;
   Recent : Recent_Array := [others => US.Null_Unbounded_String];
   Count  : Natural := 0;

   function Style return Style_Builder renames Adi.Widget_Styles.Create;

   Root_Style : constant Style_Rules :=
     (Display => Set (Flex),
      Flex_Direction => Set (Column),
      Gap => Set (Gap (Px (12.0))),
      Padding => Set (CSS_Box (Px (20.0))),
      Background_Color => Set_Bg (RGB (24, 27, 35)),
      others => <>);

   Input_Row_Style : constant Style_Rules :=
     (Display => Set (Flex),
      Flex_Direction => Set (Row),
      Gap => Set (Gap (Px (10.0))),
      others => <>);

   Text_Style : constant Style_Rules :=
     (Color => Set (RGB (225, 230, 240)),
      Font_Size => Set_Font (Px (15.0)),
      others => <>);

   Submit_Style : constant Style_Rules :=
     (Background_Color => Set_Bg (RGB (52, 112, 204)),
      Padding => Set (CSS_Box (Px (8.0), Px (14.0))),
      Border_Radius => Set (Radius (Px (6.0))),
      others => <>);

   procedure Style_Button (H : Adi.Widget.Button.Button_Handle) is
   begin
      Set_Part_Style (+H, Main_Part, Style.Base (Submit_Style).Build);
      Set_Part_Style (+H, Label_Part, Style.Base (Text_Style).Build);
   end Style_Button;

   procedure Style_Input (H : Adi.Widget.Text_Input.Text_Input_Handle) is
   begin
      Set_Part_Style (+H, Text_Part, Style.Base (Text_Style).Build);
      Set_Part_Style (+H, Main_Part, Style.Base
        ((Background_Color => Set_Bg (RGB (45, 51, 65)),
          Padding => Set (CSS_Box (Px (6.0))), others => <>)).Build);
   end Style_Input;

   procedure Refresh_Log is
      Text : US.Unbounded_String := US.Null_Unbounded_String;
   begin
      for I in 1 .. Count loop
         if I /= 1 then
            US.Append (Text, Ada.Characters.Latin_1.LF);
         end if;
         US.Append (Text, US.To_String (Recent (I)));
      end loop;
      Adi.Widget.Text_Editor.Set_Text (Output_Log, US.To_String (Text));
      Adi.Widget.Text_Editor.Scroll_To_End (Output_Log);
   end Refresh_Log;

   function Read_Sequence return FS.Sequence_View is (FS.Sequence_Of (Editor));

   procedure Refresh_Timeline is
      Seq : constant FS.Sequence_View := FS.Sequence_Of (Editor);
      Text : US.Unbounded_String := US.To_Unbounded_String ("Sources");
      Rows : Natural := 0;
   begin
      for Source of Seq.Sources loop
         if Source.Used then
            US.Append (Text, Ada.Characters.Latin_1.LF &
              Framewise.Image (Source.N) & " | " & Source.Kind'Image & " | " &
              FS.Image_Time (Source.Length) & " s | " & Framewise.Image (Source.File));
         end if;
      end loop;
      for Track of Seq.Tracks loop
         if Track.Used then
            Rows := Rows + 1;
         end if;
      end loop;
      Adi.Widget.Text_Editor.Set_Text (Sources, US.To_String (Text));
      Set_Part_Style (+Tracks, Main_Part, Style.Base
        ((Height => Set (Size (Px (Float (Natural'Max (Rows, 1) * 48 + 36)))),
          Flex_Shrink => Set (0.0),
          Background_Color => Set_Bg (RGB (32, 37, 48)), others => <>)).Build);
      Mark_Dirty (+Tracks);
   end Refresh_Timeline;

   --  All entry points share logging, execution and read-back.
   procedure Execute_Line (Line : String) is
   begin
      Adi.Widget.Text_Input.Set_Text (Command_Field, Line);
      FS.Execute (Editor, Line, Reply);
      Refresh_Timeline;
      if Count = Max_Recent then
         for I in 1 .. Max_Recent - 1 loop
            Recent (I) := Recent (I + 1);
         end loop;
      else
         Count := Count + 1;
      end if;
      Recent (Count) := US.To_Unbounded_String
        ("> " & Line & Ada.Characters.Latin_1.LF & FS.Image (Reply));
      Adi.Widget.Label.Set_Text (Status, FS.Image (Reply));
      Refresh_Log;
   end Execute_Line;

   procedure Submit is
      use Ada.Strings.Fixed;
      Line : constant String := Trim
        (Adi.Widget.Text_Input.Get_Text (Command_Field), Ada.Strings.Both);
   begin
      if Line'Length = 0 then
         return;
      end if;

      Execute_Line (Line);
      Adi.Widget.Text_Input.Set_Text (Command_Field, "");
      Set_Focus (W, +Command_Field);
   end Submit;

   procedure Submit_Clicked (Button : Widget_Handle) is
      pragma Unreferenced (Button);
   begin
      Submit;
   end Submit_Clicked;

   function Field (H : Adi.Widget.Text_Input.Text_Input_Handle) return String is
     (Ada.Strings.Fixed.Trim (Adi.Widget.Text_Input.Get_Text (H), Ada.Strings.Both));

   function Is_Token (Text : String) return Boolean is
     (Text'Length > 0 and then
      (for all C of Text => C not in ' ' | ASCII.HT | ASCII.LF | ASCII.CR));

   procedure Import_Result
     (Dialog : Widget_Handle; Index : Natural; Caption : String)
   is
      pragma Unreferenced (Dialog, Caption);
   begin
      if Index /= 1 then
         Adi.Widget.Dialog.Hide (Import_Dialog);
         return;
      end if;
      --  The current shared command grammar has no quoted tokens. Do not
      --  silently split a selected path into extra command arguments.
      if not Is_Token (Field (Import_Name)) or else
        not Is_Token (Field (Import_File)) or else
        not Is_Token (Field (Import_Length)) or else
        not Is_Token (Field (Import_Kind))
      then
         Adi.Widget.Dialog.Set_Title
           (Import_Dialog, "Use nonempty fields without spaces (current command grammar)");
         return;
      end if;
      Execute_Line ("import " & Field (Import_Name) & " " & Field (Import_File) &
                    " " & Field (Import_Length) & " " & Field (Import_Kind));
      if Reply.Ok then
         Adi.Widget.Dialog.Hide (Import_Dialog);
         --  Proxy generation is the week 7 integration in the weekly plan.
         --  For now `proxy NAME` remains available in the command bar.
      else
         Adi.Widget.Dialog.Set_Title (Import_Dialog, FS.Image (Reply));
      end if;
   end Import_Result;

   procedure File_Selected (Files : Adi.OS.String_Array) is
   begin
      if Files'Length = 0 then
         return;
      end if;
      Adi.Widget.Text_Input.Set_Text (Import_File, US.To_String (Files (Files'First)));
      Adi.Widget.Dialog.Set_Title (Import_Dialog, "Import source - duration in seconds");
      Adi.Widget.Dialog.Show (Import_Dialog);
   end File_Selected;

   procedure Import_Clicked (Button : Widget_Handle) is
      pragma Unreferenced (Button);
   begin
      Adi.OS.Show_Open_File_Dialog (File_Selected'Unrestricted_Access, W);
   end Import_Clicked;

   procedure Change_View (Button : Widget_Handle) is
      V : Timeline_View.Views.Ref := Timeline_View.Views.Borrow (Tracks);
   begin
      if Button = Widget_Handle'(+Zoom_In) then
         V.Zoom := Long_Float'Min (256.0, V.Zoom * 2.0);
      elsif Button = Widget_Handle'(+Zoom_Out) then
         V.Zoom := Long_Float'Max (8.0, V.Zoom / 2.0);
      elsif Button = Widget_Handle'(+Scroll_Left) then
         V.First_Second := Long_Float'Max (0.0, V.First_Second - 5.0);
      else
         V.First_Second := Long_Float'Min
           (Framewise.Seconds (Framewise.Time'Last / 2), V.First_Second + 5.0);
      end if;
      Adi.Widget.Label.Set_Text (View_Status,
        "Zoom" & Integer'Image (Integer (V.Zoom)) & " px/s | Start " &
        FS.Image_Time (Framewise.Time (V.First_Second * Long_Float (Framewise.Timebase))) &
        " s");
      Mark_Dirty (+Tracks);
   end Change_View;

   procedure Key_Down
     (Scancode : Adi.SDL.Events.SDL_Scancode;
      Keycode  : Adi.SDL.Events.SDL_Keycode;
      Key_Mod  : Adi.SDL.Events.SDL_Keymod;
      Repeat   : Boolean;
      Handled  : in out Boolean)
   is
      pragma Unreferenced (Keycode, Key_Mod);
   begin
      if not Repeat
        and then (Scancode = Adi.SDL.Events.SDL_SCANCODE_RETURN)
        and then Get_Focus_Handle (W) = Widget_Handle'(+Command_Field)
      then
         Handled := True;
         Submit;
      end if;
   end Key_Down;

begin
   A.Init;
   Adi.Layout_Util.Set_Px_Maps_To_Dip (True);
   A.Set_Target_FPS (60);
   W := Create_Window_Handle
     ("Framewise | Week 2", Adi.Window.Extent (Px (1100.0), Px (760.0)));

   declare
      Root  : constant Adi.Widget.Box.Box_Handle := Adi.Widget.Box.Create_Handle;
      Row   : constant Adi.Widget.Box.Box_Handle := Adi.Widget.Box.Create_Handle;
      Title : constant Adi.Widget.Label.Label_Handle :=
        Adi.Widget.Label.Create_Handle ("Framewise - command-driven video editor");
      Hint  : constant Adi.Widget.Label.Label_Handle :=
        Adi.Widget.Label.Create_Handle
          ("Type commands below (e.g. load ../examples/cut.fw, list, info c1).");
      Send : constant Adi.Widget.Button.Button_Handle :=
        Adi.Widget.Button.Create_Handle ("Run command");
      View_Row : constant Adi.Widget.Box.Box_Handle := Adi.Widget.Box.Create_Handle;
      Track_Scroll : constant Adi.Widget.Box.Box_Handle := Adi.Widget.Box.Create_Handle;
      Import_Row : constant Adi.Widget.Box.Box_Handle := Adi.Widget.Box.Create_Handle;
      Import_Name_Label : constant Adi.Widget.Label.Label_Handle :=
         Adi.Widget.Label.Create_Handle ("Source Name: ");
      Import_File_Label : constant Adi.Widget.Label.Label_Handle :=
         Adi.Widget.Label.Create_Handle ("File: ");
      Import_Length_Label : constant Adi.Widget.Label.Label_Handle :=
         Adi.Widget.Label.Create_Handle ("Length: ");
      Import_Kind_Label : constant Adi.Widget.Label.Label_Handle :=
         Adi.Widget.Label.Create_Handle ("Kind (video / audio / both): ");
   begin
      Tracks := Timeline_View.Views.New_Widget;
      Set_Flag (+Tracks, Clickable, True);
      declare
         V : Timeline_View.Views.Ref := Timeline_View.Views.Borrow (Tracks);
      begin
         V.Read_Sequence := Read_Sequence'Unrestricted_Access;
         V.Submit_Command := Execute_Line'Unrestricted_Access;
      end;
      Sources := Adi.Widget.Text_Editor.Create_Handle ("Sources");
      Adi.Widget.Text_Editor.Set_Read_Only (Sources);
      Zoom_In := Adi.Widget.Button.Create_Handle ("Zoom +");
      Zoom_Out := Adi.Widget.Button.Create_Handle ("Zoom -");
      Scroll_Left := Adi.Widget.Button.Create_Handle ("Earlier 5s");
      Scroll_Right := Adi.Widget.Button.Create_Handle ("Later 5s");
      View_Status := Adi.Widget.Label.Create_Handle ("Zoom 32 px/s | Start 0 s");
      Import_Dialog := Adi.Widget.Dialog.Create_Handle;
      Adi.Widget.Dialog.Attach_Window (Import_Dialog, W);
      Adi.Widget.Dialog.Set_Content (Import_Dialog, +Import_Row);
      Adi.Widget.Dialog.Add_Button (Import_Dialog, "Import");
      Adi.Widget.Dialog.Add_Button (Import_Dialog, "Cancel");
      Adi.Widget.Dialog.Set_Panel_Style (Import_Dialog,
        (Main_Part => (Style => Style.Base (Root_Style).Build, Enabled => True),
         others => <>));
      Adi.Widget.Dialog.Set_Title_Style (Import_Dialog,
        (Label_Part => (Style => Style.Base (Text_Style).Build, Enabled => True),
         others => <>));
      Adi.Widget.Dialog.Set_Button_Row_Style (Import_Dialog,
        (Main_Part => (Style => Style.Base (Input_Row_Style).Build, Enabled => True),
         others => <>));
      Style_Button (Adi.Widget.Dialog.Get_Button_Handle (Import_Dialog, 1));
      Style_Button (Adi.Widget.Dialog.Get_Button_Handle (Import_Dialog, 2));
      Adi.Widget.Dialog.Set_Auto_Close (Import_Dialog, False);
      Adi.Widget.Dialog.Connect_Result (Import_Dialog, Import_Result'Unrestricted_Access);
      Import_Name := Adi.Widget.Text_Input.Create_Handle ("");
      Import_File := Adi.Widget.Text_Input.Create_Handle ("");
      Import_Length := Adi.Widget.Text_Input.Create_Handle ("");
      Import_Kind := Adi.Widget.Text_Input.Create_Handle ("video");
      Import_Button := Adi.Widget.Button.Create_Handle ("Import file...");
      Adi.Widget.Text_Input.Set_Min_Visible_Chars (Import_File, 52);
      Adi.Widget.Text_Input.Set_Min_Visible_Chars (Import_Name, 24);
      Command_Field := Adi.Widget.Text_Input.Create_Handle ("");
      Adi.Widget.Text_Input.Set_Min_Visible_Chars (Command_Field, 65);
      Output_Log := Adi.Widget.Text_Editor.Create_Handle
        ("Command history and engine responses will appear here.");
      Adi.Widget.Text_Editor.Set_Read_Only (Output_Log);
      Status := Adi.Widget.Label.Create_Handle ("Ready. Load a .fw project or enter an edit.");

      Set_Part_Style (+Root, Main_Part, Style.Base (Root_Style).Build);
      Set_Part_Style (+Row, Main_Part, Style.Base (Input_Row_Style).Build);
      Set_Part_Style (+Title, Label_Part, Style.Base (Text_Style).Build);
      Set_Part_Style (+Hint, Label_Part, Style.Base (Text_Style).Build);
      Set_Part_Style (+Status, Label_Part, Style.Base (Text_Style).Build);
      Style_Button (Send);
      Style_Button (Import_Button);
      Style_Button (Zoom_In);
      Style_Button (Zoom_Out);
      Style_Button (Scroll_Left);
      Style_Button (Scroll_Right);
      Style_Input (Command_Field);
      Style_Input (Import_Name);
      Style_Input (Import_File);
      Style_Input (Import_Length);
      Style_Input (Import_Kind);
      Set_Part_Style
        (+Output_Log, Main_Part,
         Style.Base
           ((Flex_Grow => Set (1.0),
             Background_Color => Set_Bg (RGB (32, 37, 48)),
             others => <>)).Build);
      Set_Part_Style
         (+Track_Scroll, Main_Part, Style.Base
           ((Height => Set (Size (Px (250.0))), Flex_Shrink => Set (0.0),
             Overflow_Y => Set (Overflow_Auto), others => <>)).Build);
      Set_Part_Style (+Sources, Main_Part, Style.Base
        ((Height => Set (Size (Px (110.0))), Flex_Shrink => Set (0.0),
          Background_Color => Set_Bg (RGB (32, 37, 48)), others => <>)).Build);
      Set_Part_Style (+Sources, Text_Part, Style.Base (Text_Style).Build);
      Set_Part_Style (+Output_Log, Text_Part, Style.Base (Text_Style).Build);
      Set_Part_Style (+Tracks, Label_Part, Style.Base (Text_Style).Build);
      Set_Part_Style (+Tracks, Indicator_Part, Style.Base
        ((Background_Color => Set_Bg (RGB (52, 112, 204)), others => <>)).Build);
      Set_Part_Style (+View_Row, Main_Part, Style.Base (Input_Row_Style).Build);
      Set_Part_Style (+View_Status, Label_Part, Style.Base (Text_Style).Build);
      Set_Part_Style
         (+Import_Row, Main_Part, Style.Base
           ((Display => Set (Flex), Flex_Direction => Set (Column),
             Gap => Set (Gap (Px (6.0))),
             Padding => Set (CSS_Box (Px (12.0))),
             Background_Color => Set_Bg (RGB (32, 37, 48)), others => <>)).Build);
      Set_Part_Style (+Import_Name_Label, Label_Part, Style.Base (Text_Style).Build);
      Set_Part_Style (+Import_File_Label, Label_Part, Style.Base (Text_Style).Build);
      Set_Part_Style (+Import_Length_Label, Label_Part, Style.Base (Text_Style).Build);
      Set_Part_Style (+Import_Kind_Label, Label_Part, Style.Base (Text_Style).Build);

      Adi.Widget.Button.Connect_Clicked
        (Send, Submit_Clicked'Unrestricted_Access);
      Adi.Widget.Button.Connect_Clicked
        (Import_Button, Import_Clicked'Unrestricted_Access);
      Adi.Widget.Button.Connect_Clicked (Zoom_In, Change_View'Unrestricted_Access);
      Adi.Widget.Button.Connect_Clicked (Zoom_Out, Change_View'Unrestricted_Access);
      Adi.Widget.Button.Connect_Clicked (Scroll_Left, Change_View'Unrestricted_Access);
      Adi.Widget.Button.Connect_Clicked (Scroll_Right, Change_View'Unrestricted_Access);
      Connect_Key_Down (W, Key_Down'Unrestricted_Access);

      Add_Child (+Root, +Title);
      Add_Child (+Root, +Hint);
      Add_Child (+Root, +View_Row);
      Add_Child (+View_Row, +Import_Button);
      Add_Child (+View_Row, +Zoom_Out);
      Add_Child (+View_Row, +Zoom_In);
      Add_Child (+View_Row, +Scroll_Left);
      Add_Child (+View_Row, +Scroll_Right);
      Add_Child (+View_Row, +View_Status);
      Add_Child (+Import_Row, +Import_Name_Label);
      Add_Child (+Import_Row, +Import_Name);
      Add_Child (+Import_Row, +Import_File_Label);
      Add_Child (+Import_Row, +Import_File);
      Add_Child (+Import_Row, +Import_Length_Label);
      Add_Child (+Import_Row, +Import_Length);
      Add_Child (+Import_Row, +Import_Kind_Label);
      Add_Child (+Import_Row, +Import_Kind);
      Add_Child (+Root, +Track_Scroll);
      Add_Child (+Track_Scroll, +Tracks);
      Add_Child (+Root, +Sources);
      Add_Child (+Root, +Output_Log);
      Add_Child (+Root, +Status);
      Add_Child (+Row, +Command_Field);
      Add_Child (+Row, +Send);
      Add_Child (+Root, +Row);
      Set_Root (W, +Root);
      A.Add_Window (W);
      Set_Focus (W, +Command_Field);
      Refresh_Timeline;
      A.Run;
      Adi.Window.Destroy (W);
   end;
end Framewise_UI;
