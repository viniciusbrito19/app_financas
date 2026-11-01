import * as pdfjs from 'pdfjs-dist';
import worker from 'pdfjs-dist/build/pdf.worker.min.mjs?url';
import { agruparLinhas, type ItemTexto } from './linhas.ts';

pdfjs.GlobalWorkerOptions.workerSrc = worker;

/** Texto do PDF em linhas, página a página. */
export async function linhasPDF(data: ArrayBuffer, password?: string): Promise<string[]> {
	const doc = await pdfjs.getDocument({ data, password }).promise;
	const linhas: string[] = [];
	for (let p = 1; p <= doc.numPages; p++) {
		const { items } = await (await doc.getPage(p)).getTextContent();
		linhas.push(...agruparLinhas(items as ItemTexto[]));
	}
	if (!linhas.length) throw new Error('Este PDF não tem texto (é uma imagem). Use o PDF original da fatura, baixado do app ou do site.');
	return linhas;
}
