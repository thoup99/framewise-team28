with Adi.Widget; use Adi.Widget;
with Adi.Window; use Adi.Window;
with Framewise;
with Timeline_View;
with Editor_Context; use Editor_Context;
with Editor_Controller; use Editor_Controller;
with Editor_Timeline_Actions;
with Editor_Console;
with Editor_Export;

package body Editor_Shortcuts is
   use type Buttons.Button_Handle;
   use type Inputs.Text_Input_Handle;
   use type Timeline_View.Views.Handle;
   use type Adi.SDL.Events.SDL_Scancode;
   use type Framewise.Time;

   Key_N : constant Adi.SDL.Events.SDL_Scancode := 17;
   Key_O : constant Adi.SDL.Events.SDL_Scancode := 18;
   Key_R : constant Adi.SDL.Events.SDL_Scancode := 21;
   Key_S : constant Adi.SDL.Events.SDL_Scancode := 22;

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

      --  Editable numeric fields own their keys while the user is typing.
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
         Editor_Timeline_Actions.Delete_Selected;
      elsif not Ctrl and then Get_Focus_Handle (W) = Widget_Handle'(+Tracks) then
         if Scancode = Key_R then
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
                  Timeline_View.Set_Playhead
                    (V.Ptr.all, V.Playhead - Framewise.Time'Min (V.Playhead, Step));
               else
                  Timeline_View.Set_Playhead
                    (V.Ptr.all, V.Playhead + Framewise.Time'Min (Step, Framewise.Time'Last / 2 - V.Playhead));
               end if;
            end;
         else
            return;
         end if;
      else
         return;
      end if;
      Handled := True;
   end Key_Down;
end Editor_Shortcuts;
