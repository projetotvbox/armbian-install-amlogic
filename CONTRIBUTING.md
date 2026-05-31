# 📖 Guia de Contribuição

> **Language / Idioma:** [English](CONTRIBUTING.en.md) | **[🟢 Português]**

Obrigado por considerar contribuir com o **Armbian Installer for AMLogic TV Boxes**! 

Todas as contribuições são bem-vindas! Existem várias formas de contribuir com o projeto:

---

## 🆕 Contribuindo com Novos Dispositivos

Se você extraiu variáveis U-Boot e criou um perfil funcional para um novo dispositivo:

### 1. Prepare os arquivos

- **Profile (`.conf`)** em `armbian-install-amlogic/profiles/`
- **Asset compactado (`.img.gz`)** em `armbian-install-amlogic/assets/`

### 2. ⚠️ IMPORTANTE para assets

- ✅ Sempre commite arquivos `.img.gz` (compactados)
- ❌ **NUNCA** commite `.img` (descompactados)
- O `.gitignore` está configurado para aceitar apenas `.img.gz`
- Verifique o tamanho do arquivo (deve ser <100MB)

### 3. Documente

Inclua na descrição do Pull Request:

- Especificações do dispositivo (SoC, RAM, storage)
- Método usado para extração (Wipe & Regen ou Ampart)
- Peculiaridades encontradas durante testes
- Fotos dos pontos de soldagem da serial (se possível)

### 4. Submeta via Pull Request

Siga o fluxo padrão de contribuição descrito abaixo.

---

## 🐛 Reportando Bugs

Encontrou um problema? Ajude-nos a corrigir!

1. Acesse a aba [Issues](https://github.com/projetotvbox/armbian-install-amlogic/issues)
2. Verifique se o problema já foi reportado
3. Abra uma nova issue incluindo:
   - Modelo do dispositivo (TV Box)
   - Logs completos (`/tmp/armbian-install-amlogic.log`)
   - Steps detalhados para reproduzir o problema
   - Versão do Armbian utilizada

---

## 📝 Melhorando Documentação

Documentação clara é essencial! Contribuições incluem:

- ✍️ Correções de typos e erros gramaticais
- 📚 Clarificações e melhorias de texto
- 🌐 Traduções para outros idiomas
- 📊 Exemplos adicionais ou diagramas
- 🎥 Tutoriais em vídeo ou imagens ilustrativas

---

## 💻 Contribuindo com Código

### Fluxo Padrão de Contribuição

1. **Fork o repositório**
   ```bash
   # Clique em "Fork" no GitHub
   ```

2. **Clone seu fork**
   ```bash
   git clone https://github.com/seu-usuario/armbian-install-amlogic.git
   cd armbian-install-amlogic
   ```

3. **Crie uma branch para sua feature**
   ```bash
   git checkout -b feature/MinhaFeature
   # Exemplos de nomes:
   # - feature/suporte-device-xyz
   # - fix/corrige-bug-particao
   # - docs/atualiza-instalacao
   ```

4. **Faça suas alterações**
   - Edite os arquivos necessários
   - Teste extensivamente

5. **Commit suas mudanças**
   ```bash
   git add .
   git commit -m 'Adiciona suporte para Device XYZ'
   ```
   
   **Dicas para mensagens de commit:**
   - Use verbos no imperativo ("Adiciona", "Corrige", "Atualiza")
   - Seja específico e descritivo
   - Limite primeira linha a 50-72 caracteres
   - Adicione detalhes no corpo se necessário

6. **Push para seu fork**
   ```bash
   git push origin feature/MinhaFeature
   ```

7. **Abra um Pull Request**
   - Acesse seu fork no GitHub
   - Clique em "Compare & pull request"
   - Preencha a descrição detalhadamente:
     - O que foi alterado?
     - Por que foi alterado?
     - Como testar?
     - Issues relacionadas (se houver)

---

## ✅ Boas Práticas

Ao contribuir com código, siga estas diretrizes:

### Testes

- ✅ Teste extensivamente antes de submeter
- ✅ Verifique em pelo menos um dispositivo real
- ✅ Valide boot bem-sucedido da eMMC
- ✅ Teste cenários de erro (ex: cancelamento, falta de espaço)

### Commits

- ✅ Mantenha commits atômicos (uma mudança lógica por commit)
- ✅ Use mensagens descritivas
- ✅ Evite commits com "WIP" ou "teste" no histórico final

### Código

- ✅ Siga o estilo de código existente (bash script style)
- ✅ Adicione comentários para lógica complexa
- ✅ Use nomes de variáveis descritivos
- ✅ Valide entrada do usuário adequadamente

### Documentação

- ✅ Atualize README.md se adicionar features
- ✅ Atualize comentários no código
- ✅ Mantenha paridade entre versões PT-BR e EN

---

## 📋 Checklist de Pull Request

Antes de submeter, verifique:

- [ ] Código testado em dispositivo real
- [ ] Assets de U-Boot compactados (`.img.gz`)
- [ ] Documentação atualizada (se aplicável)
- [ ] Commits organizados e descritivos
- [ ] Nenhum arquivo temporário ou de log incluído
- [ ] Mensagens de erro claras e úteis
- [ ] Compatível com estrutura existente

---

## 💡 Dúvidas?

Se tiver dúvidas sobre como contribuir:

1. Leia a documentação completa no [README.md](README.md)
2. Consulte issues existentes no [GitHub Issues](https://github.com/projetotvbox/armbian-install-amlogic/issues)
3. Abra uma discussão em [Discussions](https://github.com/projetotvbox/armbian-install-amlogic/discussions) (se habilitado)

---

## 🙏 Agradecimentos

**🎉 Toda contribuição, por menor que seja, faz diferença!**

Este projeto é mantido por voluntários e faz parte de uma iniciativa social do **IFSP Campus Salto**. Sua contribuição ajuda a:

- ♻️ Reduzir lixo eletrônico
- 🎓 Promover inclusão digital
- 🔧 Ensinar tecnologia para estudantes
- 🌍 Criar impacto social positivo

**Obrigado por fazer parte dessa iniciativa!** ❤️

---

## 📄 Código de Conduta

Este projeto segue os princípios de respeito, colaboração e inclusão. Esperamos que todos os contribuidores:

- Sejam respeitosos e construtivos
- Aceitem críticas construtivas
- Foquem no melhor para a comunidade
- Demonstrem empatia com outros membros

---

**Desenvolvido para o Projeto TVBox - Instituto Federal de São Paulo (IFSP), Campus Salto**
