import * as pdfjs from 'pdfjs-dist';
import worker from 'pdfjs-dist/build/pdf.worker.min.mjs?url';
import { agruparColunas, agruparLinhas, type ItemTexto } from './linhas.ts';
import type { TextoPDF } from './tipos.ts';

pdfjs.GlobalWorkerOptions.workerSrc = worker;

/** Texto do PDF, página a página. */
export async function textoPDF(data: ArrayBuffer, password?: string): Promise<TextoPDF> {
	const doc = await pdfjs.getDocument({ data, password }).promise;
	const texto: TextoPDF = { linhas: [], colunas: [] };
	for (let p = 1; p <= doc.numPages; p++) {
		const pagina = await doc.getPage(p);
		const items = (await pagina.getTextContent()).items as ItemTexto[];
		texto.linhas.push(...agruparLinhas(items));
		texto.colunas.push(...agruparColunas(items, pagina.view[2]));
	}
	if (!texto.linhas.length) throw new Error('Este PDF não tem texto (é uma imagem). Use o PDF original da fatura, baixado do app ou do site.');
	return texto;
}
