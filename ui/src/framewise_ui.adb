--  Framewise week 1: Adi2 window and a GUI command bar.
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
   Timeline_View : Adi.Widget.Text_Editor.Text_Editor_Handle;
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

   procedure Refresh_Timeline is
      Seq : constant FS.Sequence_View := FS.Sequence_Of (Editor);
      Text : US.Unbounded_String := US.To_Unbounded_String ("Timeline");
   begin
      for T in Seq.Tracks'Range loop
         if Seq.Tracks (T).Used then
            US.Append
            (Text,
               Ada.Characters.Latin_1.LF &
               Framewise.Image (Seq.Tracks (T).N));

            for I in 1 .. Seq.Tracks (T).Count loop
               US.Append
               (Text,
                  Ada.Characters.Latin_1.LF &
                  " " & Framewise.Image (Seq.Tracks (T).Clips (I).N) &
                  " " &
                  FS.Image_Time
                    (Seq.Tracks (T).Clips (I).Start) &
                  " - " &
                 FS.Image_Time
                   (Seq.Tracks (T).Clips (I).Start +
                    (Seq.Tracks (T).Clips (I).Src_Out -
                     Seq.Tracks (T).Clips (I).Src_In)));
            end loop;
         end if;
      end loop;

      Adi.Widget.Text_Editor.Set_Text
      (Timeline_View, US.To_String (Text));
   end Refresh_Timeline;

   procedure Submit is
      use Ada.Strings.Fixed;
      Line : constant String := Trim
        (Adi.Widget.Text_Input.Get_Text (Command_Field), Ada.Strings.Both);
   begin
      if Line'Length = 0 then
         return;
      end if;

      --  No alternative edit path: the same command and response that
      --  the CLI and agents use, and no local copy of the sequence.
      FS.Execute (Editor, Line, Reply);
      Refresh_Timeline;
      declare
         Log_Item : constant US.Unbounded_String :=
         US.To_Unbounded_String ("> " & Line & Ada.Characters.Latin_1.LF
            & FS.Image (Reply));
      begin
         if Count = Max_Recent then
            for I in 1 .. Max_Recent - 1 loop
               Recent (I) := Recent (I + 1);
            end loop;
         else
            Count := Count + 1;
         end if;
         Recent (Count) := Log_Item;
      end;

      Adi.Widget.Label.Set_Text (Status, FS.Image (Reply));
      Refresh_Log;
      Adi.Widget.Text_Input.Set_Text (Command_Field, "");
      Set_Focus (W, +Command_Field);
   end Submit;

   procedure Submit_Clicked (Button : Widget_Handle) is
      pragma Unreferenced (Button);
   begin
      Submit;
   end Submit_Clicked;

   procedure Import_Clicked (Button : Widget_Handle) is
      pragma Unreferenced (Button);

      Name_Text : constant string :=
         Ada.Strings.Fixed.Trim
            (Adi.Widget.Text_Input.Get_Text (Import_Name), Ada.Strings.Both);

      File_Text : constant String :=
         Ada.Strings.Fixed.Trim
            (Adi.Widget.Text_Input.Get_Text (Import_File), Ada.Strings.Both);

      Length_Text : constant String :=
         Ada.Strings.Fixed.Trim
            (Adi.Widget.Text_Input.Get_Text (Import_Length), Ada.Strings.Both);

      Kind_Text : constant String :=
         Ada.Strings.Fixed.Trim
            (Adi.Widget.Text_Input.Get_Text  (Import_Kind), Ada.Strings.Both);

      Line : constant String :=
         "import "  & Name_Text & " " & File_Text & " " &
         Length_Text & " " & Kind_Text;
   begin
      FS.Execute (Editor, Line, Reply);
      Refresh_Timeline;

      Adi.Widget.Label.Set_Text (Status, FS.Image (Reply));
   end Import_Clicked; 

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
     ("Framewise | Week 1", Adi.Window.Extent (Px (920.0), Px (600.0)));

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
      Import_Row : constant Adi.Widget.Box.Box_Handle := Adi.Widget.Box.Create_Handle;
      Import_Name_Label : constant Adi.Widget.Label.Label_Handle :=
         Adi.Widget.Label.Create_Handle ("Source Name: ");
      Import_File_Label : constant Adi.Widget.Label.Label_Handle :=
         Adi.Widget.Label.Create_Handle ("File: ");
      Import_Length_Label : constant Adi.Widget.Label.Label_Handle :=
         Adi.Widget.Label.Create_Handle ("Length: ");
      Import_Kind_Label : constant Adi.Widget.Label.Label_Handle :=
         Adi.Widget.Label.Create_Handle ("Kind: ");
   begin
      Timeline_View := Adi.Widget.Text_Editor.Create_Handle ("Timeline");
        Adi.Widget.Text_Editor.Set_Read_Only (Timeline_View);
      Import_Name := Adi.Widget.Text_Input.Create_Handle ("");
      Import_File := Adi.Widget.Text_Input.Create_Handle ("");
      Import_Length := Adi.Widget.Text_Input.Create_Handle ("");
      Import_Kind := Adi.Widget.Text_Input.Create_Handle ("video");
      Import_Button := Adi.Widget.Button.Create_Handle ("Import");
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
      Set_Part_Style (+Send, Main_Part, Style.Base (Submit_Style).Build);
      Set_Part_Style (+Send, Label_Part, Style.Base (Text_Style).Build);
      Set_Part_Style
        (+Output_Log, Main_Part,
         Style.Base
           ((Flex_Grow => Set (1.0),
             Background_Color => Set_Bg (RGB (32, 37, 48)),
             others => <>)).Build);
      Set_Part_Style
         (+Timeline_View, Main_Part,
         Style.Base
            ((Flex_Grow => Set (0.35),
               Background_Color => Set_Bg (RGB (32, 37, 48)),
               others => <>)).Build);
      Set_Part_Style
         (+Import_Row, Main_Part, Style.Base (Input_Row_Style).Build);
      Set_Part_Style (+Import_Name_Label, Label_Part, Style.Base (Text_Style).Build);
      Set_Part_Style (+Import_File_Label, Label_Part, Style.Base (Text_Style).Build);
      Set_Part_Style (+Import_Length_Label, Label_Part, Style.Base (Text_Style).Build);
      Set_Part_Style (+Import_Kind_Label, Label_Part, Style.Base (Text_Style).Build);

      Adi.Widget.Button.Connect_Clicked
        (Send, Submit_Clicked'Unrestricted_Access);
      Adi.Widget.Button.Connect_Clicked
        (Import_Button, Import_Clicked'Unrestricted_Access);
      Connect_Key_Down (W, Key_Down'Unrestricted_Access);

      Add_Child (+Root, +Title);
      Add_Child (+Root, +Hint);
      Add_Child (+Root, +Import_Row);
      Add_Child (+Import_Row, +Import_Name_Label);
      Add_Child (+Import_Row, +Import_Name);
      Add_Child (+Import_Row, +Import_File_Label);
      Add_Child (+Import_Row, +Import_File);
      Add_Child (+Import_Row, +Import_Length_Label);  
      Add_Child (+Import_Row, +Import_Length);
      Add_Child (+Import_Row, +Import_Kind_Label);
      Add_Child (+Import_Row, +Import_Kind);
      Add_Child (+Import_Row, +Import_Button);
      Add_Child (+Root, +Timeline_View);
      Add_Child (+Root, +Output_Log);
      Add_Child (+Root, +Status);
      Add_Child (+Row, +Command_Field);
      Add_Child (+Row, +Send);
      Add_Child (+Root, +Row);
      Set_Root (W, +Root);
      A.Add_Window (W);
      Set_Focus (W, +Command_Field);
      A.Run;
   end;
end Framewise_UI;
