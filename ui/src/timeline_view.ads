
--  Timeline presentation and mouse-based clip movement.
with Ada.Strings.Unbounded;
with Adi.Core;
with Adi.SDL.Mouse;
with Adi.SDL.Events;
with Adi.Widget;
with Adi.Widget.Extension;
with Framewise.Session;

package Timeline_View is
   type Sequence_Reader is access function
     return Framewise.Session.Sequence_View;

   type Command_Callback is access procedure (Line : String);

   type Track_Widget is new Adi.Widget.Widget with record
      Read_Sequence  : Sequence_Reader;
      Submit_Command : Command_Callback := null;
      Snap_Interval  : Framewise.Time := Framewise.Time (Framewise.Timebase / 2);
      Zoom           : Long_Float := 32.0;
      First_Second   : Long_Float := 0.0;
      Playhead       : Framewise.Time := 0;
      Scrubbing      : Boolean := False;
      Preview_Changed : Command_Callback := null;
      Razor_Mode : Boolean := False;
      Razor_Hover : Boolean := False;
      Razor_X, Razor_Y : Adi.Core.Pixel_Type := 0.0;
      Selected_Clip : Ada.Strings.Unbounded.Unbounded_String;
      Selection_Changed : Command_Callback := null;

      Drag_Modifiers  : Adi.SDL.Events.SDL_Keymod := 0;
      Drag_Active     : Boolean := False;
      Drag_Name       : Ada.Strings.Unbounded.Unbounded_String;
      Drag_Start_X    : Adi.Core.Pixel_Type := 0.0;
      Drag_Current_X  : Adi.Core.Pixel_Type := 0.0;
      Drag_Start_Time : Long_Float := 0.0;
      Drag_Trim_Left  : Boolean := False;
      Drag_Trim_Right : Boolean := False;
      Drag_Src_In     : Long_Float := 0.0;
      Drag_Src_Out    : Long_Float := 0.0;
   end record;

   procedure Set_Razor_Pointer (W : in out Track_Widget;
      X, Y : Adi.Core.Pixel_Type; Active : Boolean);
   function Cursor_At (W : Track_Widget; X, Y : Adi.Core.Pixel_Type)
      return Adi.SDL.Mouse.SDL_SystemCursor;
   function Preview_Text
     (Seq : Framewise.Session.Sequence_View; At_Time : Framewise.Time) return String;

   overriding procedure Layout (W : in out Track_Widget) is null;
   overriding procedure Build_Items (W : in out Track_Widget);

   overriding procedure On_Mouse_Down
     (W      : in out Track_Widget;
      X, Y   : Adi.Core.Pixel_Type;
      Button : Adi.Core.Mouse_Button;
      Clicks : Natural := 1);

   overriding procedure On_Mouse_Move
      (W    : in out Track_Widget;
       X, Y : Adi.Core.Pixel_Type);

   overriding procedure On_Mouse_Up
     (W      : in out Track_Widget;
      X, Y   : Adi.Core.Pixel_Type;
      Button : Adi.Core.Mouse_Button);

   overriding procedure On_Key_Down
     (W : in out Track_Widget; Scancode : Adi.SDL.Events.SDL_Scancode;
      Key_Mod : Adi.SDL.Events.SDL_Keymod; Repeat : Boolean);

   overriding procedure On_Key_Up
     (W : in out Track_Widget; Scancode : Adi.SDL.Events.SDL_Scancode;
      Key_Mod : Adi.SDL.Events.SDL_Keymod; Repeat : Boolean);

   package Views is new Adi.Widget.Extension (Track_Widget);
end Timeline_View;
