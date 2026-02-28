# 📖 Contribution Guide

> **Language / Idioma:** **[🟢 English]** | [Português](CONTRIBUTING.md)

Thank you for considering contributing to the **Armbian Installer for AMLogic TV Boxes**!

All contributions are welcome! There are several ways to contribute to the project:

---

## 🆕 Contributing New Devices

If you extracted U-Boot variables and created a working profile for a new device:

### 1. Prepare the files

- **Profile (`.conf`)** in `armbian-install-amlogic/profiles/`
- **Compressed asset (`.img.gz`)** in `armbian-install-amlogic/assets/`

### 2. ⚠️ IMPORTANT for assets

- ✅ Always commit `.img.gz` files (compressed)
- ❌ **NEVER** commit `.img` (uncompressed)
- `.gitignore` is configured to accept only `.img.gz`
- Check file size (should be <100MB)

### 3. Document

Include in the Pull Request description:

- Device specifications (SoC, RAM, storage)
- Method used for extraction (Wipe & Regen or Ampart)
- Peculiarities found during testing
- Photos of serial soldering points (if possible)

### 4. Submit via Pull Request

Follow the standard contribution workflow described below.

---

## 🐛 Reporting Bugs

Found a problem? Help us fix it!

1. Go to [Issues](https://github.com/projetotvbox/armbian-install-amlogic-project/issues) tab
2. Check if the problem has already been reported
3. Open a new issue including:
   - Device model (TV Box)
   - Complete logs (`/tmp/armbian-install-amlogic.log`)
   - Detailed steps to reproduce the problem
   - Armbian version used

---

## 📝 Improving Documentation

Clear documentation is essential! Contributions include:

- ✍️ Typo and grammar corrections
- 📚 Text clarifications and improvements
- 🌐 Translations to other languages
- 📊 Additional examples or diagrams
- 🎥 Video tutorials or illustrative images

---

## 💻 Contributing Code

### Standard Contribution Workflow

1. **Fork the repository**
   ```bash
   # Click "Fork" on GitHub
   ```

2. **Clone your fork**
   ```bash
   git clone https://github.com/your-username/armbian-install-amlogic-project.git
   cd armbian-install-amlogic-project
   ```

3. **Create a branch for your feature**
   ```bash
   git checkout -b feature/MyFeature
   # Example names:
   # - feature/support-device-xyz
   # - fix/partition-bug
   # - docs/update-installation
   ```

4. **Make your changes**
   - Edit necessary files
   - Test extensively

5. **Commit your changes**
   ```bash
   git add .
   git commit -m 'Add support for Device XYZ'
   ```
   
   **Tips for commit messages:**
   - Use imperative verbs ("Add", "Fix", "Update")
   - Be specific and descriptive
   - Limit first line to 50-72 characters
   - Add details in body if necessary

6. **Push to your fork**
   ```bash
   git push origin feature/MyFeature
   ```

7. **Open a Pull Request**
   - Go to your fork on GitHub
   - Click "Compare & pull request"
   - Fill description in detail:
     - What was changed?
     - Why was it changed?
     - How to test?
     - Related issues (if any)

---

## ✅ Best Practices

When contributing code, follow these guidelines:

### Testing

- ✅ Test extensively before submitting
- ✅ Verify on at least one real device
- ✅ Validate successful eMMC boot
- ✅ Test error scenarios (e.g., cancellation, out of space)

### Commits

- ✅ Keep commits atomic (one logical change per commit)
- ✅ Use descriptive messages
- ✅ Avoid commits with "WIP" or "test" in final history

### Code

- ✅ Follow existing code style (bash script style)
- ✅ Add comments for complex logic
- ✅ Use descriptive variable names
- ✅ Validate user input properly

### Documentation

- ✅ Update README.md if adding features
- ✅ Update code comments
- ✅ Maintain parity between PT-BR and EN versions

---

## 📋 Pull Request Checklist

Before submitting, verify:

- [ ] Code tested on real device
- [ ] U-Boot assets compressed (`.img.gz`)
- [ ] Documentation updated (if applicable)
- [ ] Commits organized and descriptive
- [ ] No temporary or log files included
- [ ] Clear and helpful error messages
- [ ] Compatible with existing structure

---

## 💡 Questions?

If you have questions about contributing:

1. Read the complete documentation in [README.en.md](README.en.md)
2. Check existing issues on [GitHub Issues](https://github.com/projetotvbox/armbian-install-amlogic-project/issues)
3. Start a discussion in [Discussions](https://github.com/projetotvbox/armbian-install-amlogic-project/discussions) (if enabled)

---

## 🙏 Acknowledgments

**🎉 Every contribution, no matter how small, makes a difference!**

This project is maintained by volunteers and is part of a social initiative by **IFSP Campus Salto**. Your contribution helps to:

- ♻️ Reduce electronic waste
- 🎓 Promote digital inclusion
- 🔧 Teach technology to students
- 🌍 Create positive social impact

**Thank you for being part of this initiative!** ❤️

---

## 📄 Code of Conduct

This project follows principles of respect, collaboration, and inclusion. We expect all contributors to:

- Be respectful and constructive
- Accept constructive criticism
- Focus on what's best for the community
- Show empathy towards other members

---

**Developed for Projeto TVBox - Instituto Federal de São Paulo (IFSP), Campus Salto**
