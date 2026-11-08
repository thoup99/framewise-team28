with Adi.Widget_Styles; use Adi.Widget_Styles;
with Adi.Core; use Adi.Core;
with Adi.Widget; use Adi.Widget;
with Adi.Window; use Adi.Window;
with Timeline_View;
with Editor_Split;
with Editor_Context; use Editor_Context;
with Adi.SDL.Mouse;
with Adi.SDL.Video;

package body Editor_Cursors is
   use type Buttons.Button_Handle;
   use type Inputs.Text_Input_Handle;
   use type Combos.Combo_Box_Handle;
   use type Timeline_View.Views.Handle;
   use type Editor_Split.Views.Handle;
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
            Controls : constant Handles := [+Filter_Buttons (All_Media),
              +Filter_Buttons (Video_Media), +Filter_Buttons (Audio_Media),
              +Console_Button, +File_Button, +Add_Track_Button, +Place_Button,
              +Undo_Button, +Delete_Button, +Razor_Button, +Move_Button,
              +Zoom_In, +Zoom_Out, +Scroll_Left, +Scroll_Right, +Start_Button, +End_Button,
              +Source_Choice, +Track_Choice, +Kind_Choice,
              +Dialogs.Get_Button_Handle (Form, 1), +Dialogs.Get_Button_Handle (Form, 2),
              +Dialogs.Get_Button_Handle (Confirm, 1), +Dialogs.Get_Button_Handle (Confirm, 2),
              +Console_Run_Button, +Console_Close_Button];
         begin
            for H of Controls loop
               if Has_State (H, State_Hovered) then
                  Kind := Mouse.SDL_SYSTEM_CURSOR_POINTER;
                  exit;
               end if;
            end loop;
            if Has_State (+Console_Input, State_Hovered) or else
              Has_State (+Snap_Interval_Input, State_Hovered)
            then
               Kind := Mouse.SDL_SYSTEM_CURSOR_TEXT;
            end if;
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

   procedure Connect is
   begin
      Connect_Frame (W, Update_Cursor'Access);
   end Connect;

   procedure Release is
   begin
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
      Cursors := [others => null];
   end Release;
end Editor_Cursors;
