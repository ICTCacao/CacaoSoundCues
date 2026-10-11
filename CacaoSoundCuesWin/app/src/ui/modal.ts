// 確認のダイアログ（ボタンを選んでもらう）と、お知らせ
import { signal } from "@preact/signals";

export interface ModalButton { label: string; kind?: "primary" | "danger" }
export interface ModalRequest { title: string; text?: string; buttons: ModalButton[]; resolve: (index: number) => void }

export const modal = signal<ModalRequest | null>(null);

/** ボタンを選んでもらう。選んだボタンの番号を返す（閉じたら -1） */
export function choose(title: string, text: string | undefined, buttons: ModalButton[]): Promise<number> {
  return new Promise(resolve => {
    modal.value = {
      title, text, buttons,
      resolve: i => { modal.value = null; resolve(i); },
    };
  });
}
