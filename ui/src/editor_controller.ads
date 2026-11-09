with Adi.Core;
with Adi.Widget; use Adi.Widget;
with Adi.Window; use Adi.Window;
with Adi.OS;
with Adi.SDL.Events;
with Editor_Context; use Editor_Context;

package Editor_Controller is
   --  All document changes pass through Session.Execute here.
   procedure Update_Filter_Buttons;

   procedure Reset_File_Menu;

   procedure Tell (Text : String);

   --  Surface validation failures that occur before a session command runs.
   procedure Report_Editor_Error (Action, Message : String);

   procedure Snap_Interval_Changed (Input : Widget_Handle; Text : String);

   function History return US.Unbounded_String;

   function Read_Sequence return FS.Sequence_View;

   procedure Show_Preview (Text : String);

   procedure Refresh_Timeline;

   procedure Execute_Line (Line : String);

   --  Execute console commands and synchronize save/load document bookkeeping.
   procedure Execute_Console_Line (Line : String);

   function Valid_Path (Text, Action : String) return Boolean;

   function Unique_Name (Prefix : String) return String;

   procedure Save_Selected (Files : Adi.OS.String_Array);

   procedure Save_Project (Save_As : Boolean := False);

   procedure Open_Selected (Files : Adi.OS.String_Array);

   procedure Request_Action (Action : Pending_Action);

   procedure Confirm_Result (Dialog : Widget_Handle; Index : Natural; Caption : String);

   procedure Close_Requested (Window : Window_Handle; Allow : in out Boolean);

   procedure Export_Selected (Files : Adi.OS.String_Array);

   procedure Clip_Selected (Name : String);

   procedure Clicked (Button : Widget_Handle);

   procedure Show_Clip_Menu (Widget : Widget_Handle; X, Y : Adi.Core.Pixel_Type);

   procedure Clip_Menu_Selected (Menu : Menus.Menu_Handle; Index : Positive; Text : String);

   procedure Menu_Selected (Menu : Menus.Menu_Handle; Index : Positive; Text : String);

   procedure Key_Down
     (Scancode : Adi.SDL.Events.SDL_Scancode;
      Keycode : Adi.SDL.Events.SDL_Keycode;
      Key_Mod : Adi.SDL.Events.SDL_Keymod;
      Repeat : Boolean; Handled : in out Boolean);
end Editor_Controller;
