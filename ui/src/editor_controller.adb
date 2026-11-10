with Ada.Characters.Latin_1;
with Ada.Strings.Fixed;
with Adi.CSS_Styles; use Adi.CSS_Styles;
with Adi.Widget_Styles; use Adi.Widget_Styles;
with Adi.Widget.Text_Editor;
with Framewise;
with Timeline_View;
with Editor_Styles; use Editor_Styles;
with Editor_Console;

package body Editor_Controller is
   use type Buttons.Button_Handle;
   use type Labels.Label_Handle;
   use type Combos.Combo_Box_Handle;
   use type Adi.Widget.Text_Editor.Text_Editor_Handle;
   use type Timeline_View.Views.Handle;
   use type US.Unbounded_String;

   --  Generated UI names are an implementation detail, not shared view state.
   Serial : Natural := 0;

   procedure Apply_Command (Line : String; Origin : Editor_Console.Command_Origin);

   function Matches_Filter (Kind : FS.Media_Kind) return Boolean is
     (case Current_Filter is
         when All_Media => True,
         when Video_Media => Kind'Image in "VIDEO" | "BOTH",
         when Audio_Media => Kind'Image in "AUDIO" | "BOTH");

   function Read_Sequence return FS.Sequence_View is (FS.Sequence_Of (Editor));

   function Safe_Path (Text : String) return Boolean is
     (Text'Length > 0 and then Text'Length <= 240 and then
      (for all C of Text => C in 'a' .. 'z' | 'A' .. 'Z' | '0' .. '9' |
        '/' | '\' | ':' | '.' | '_' | '-' | ' '));

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

   function History return US.Unbounded_String is
      Result : US.Unbounded_String;
   begin
      for I in 1 .. FS.History_Length (Editor) loop
         US.Append (Result, FS.History_Line (Editor, I) & Ada.Characters.Latin_1.LF);
      end loop;
      return Result;
   end History;

   procedure Refresh_Timeline is
      Seq : constant FS.Sequence_View := FS.Sequence_Of (Editor);
      Text : US.Unbounded_String;
      Old_Source : constant String := Combos.Get_Selected_Text (Source_Choice);
      Old_Track : constant String := Combos.Get_Selected_Text (Track_Choice);
      Rows : Natural := 0;
   begin
      Combos.Clear_Items (Source_Choice);
      Combos.Clear_Items (Track_Choice);

      --  Preserve selections while rebuilding the filtered project views.
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

      Editor_Project_Actions.Update_Title;
      Mark_Dirty (+Tracks);
   end Refresh_Timeline;

   procedure Apply_Command (Line : String; Origin : Editor_Console.Command_Origin) is
   begin
      --  Buttons, gestures and console submissions share execution, refresh
      --  and logging so an edit is always recorded exactly once.
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

   procedure Execute_Console_Command (Line : String) is
   begin
      Apply_Command (Line, Editor_Console.Console_Command);
   end Execute_Console_Command;

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
         Editor_Project_Actions.Show_File_Menu (Button);
      else
         Editor_Timeline_Actions.Clicked (Button);
      end if;
   end Clicked;
end Editor_Controller;
