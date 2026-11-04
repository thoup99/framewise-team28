
--  Timeline presentation and mouse-based clip movement.
with Ada.Strings.Unbounded;
with Adi.Core;
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
      Zoom           : Long_Float := 32.0;
      First_Second   : Long_Float := 0.0;
      Razor_Mode : Boolean := False;

      Drag_Active     : Boolean := False;
      Drag_Name       : Ada.Strings.Unbounded.Unbounded_String;
      Drag_Start_X    : Adi.Core.Pixel_Type := 0.0;
      Drag_Start_Time : Long_Float := 0.0;
      Drag_Trim_Right : Boolean := False;
      Drag_Src_In     : Long_Float := 0.0;
      Drag_Src_Out    : Long_Float := 0.0;
   end record;

   overriding procedure Layout (W : in out Track_Widget) is null;
   overriding procedure Build_Items (W : in out Track_Widget);

   overriding procedure On_Mouse_Down
     (W      : in out Track_Widget;
      X, Y   : Adi.Core.Pixel_Type;
      Button : Adi.Core.Mouse_Button;
      Clicks : Natural := 1);

   overriding procedure On_Mouse_Up
     (W      : in out Track_Widget;
      X, Y   : Adi.Core.Pixel_Type;
      Button : Adi.Core.Mouse_Button);

   package Views is new Adi.Widget.Extension (Track_Widget);
end Timeline_View;
