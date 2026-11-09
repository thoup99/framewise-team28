with Adi.SDL.Events;

package Editor_Shortcuts is
   --  Honor modal dialogs and text-field focus before dispatching shortcuts.
   procedure Key_Down
     (Scancode : Adi.SDL.Events.SDL_Scancode;
      Keycode : Adi.SDL.Events.SDL_Keycode;
      Key_Mod : Adi.SDL.Events.SDL_Keymod;
      Repeat : Boolean; Handled : in out Boolean);
end Editor_Shortcuts;
