with Adi.Core;
with Adi.Widget; use Adi.Widget;
with Editor_Context; use Editor_Context;

package Editor_Timeline_Actions is
   --  View controls and clip actions. Edits still go through the controller.
   procedure Snap_Interval_Changed (Input : Widget_Handle; Text : String);
   procedure Cursor_Time_Changed (Input : Widget_Handle; Text : String);
   procedure Show_Preview (Text : String);
   procedure Reset_View;
   procedure Clip_Selected (Name : String);
   procedure Delete_Selected;
   procedure Clicked (Button : Widget_Handle);
   procedure Show_Clip_Menu (Widget : Widget_Handle; X, Y : Adi.Core.Pixel_Type);
   procedure Clip_Menu_Selected (Menu : Menus.Menu_Handle; Index : Positive; Text : String);
end Editor_Timeline_Actions;
