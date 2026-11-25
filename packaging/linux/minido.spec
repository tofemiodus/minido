Name:           minido
Version:        @APP_VERSION@
Release:        1
Summary:        Offline-first personal to-do app
License:        Unknown
BuildArch:      x86_64
Source0:        Minido-Linux-x64.tar.gz
Source1:        minido.desktop
Source2:        minido.png

%description
Minido is an offline-first personal to-do app.

%prep
%setup -q -n Minido-Linux-x64

%build

%install
mkdir -p %{buildroot}/opt/minido
cp -a . %{buildroot}/opt/minido/
mkdir -p %{buildroot}/usr/share/applications
install -m 0644 %{SOURCE1} %{buildroot}/usr/share/applications/minido.desktop
mkdir -p %{buildroot}/usr/share/icons/hicolor/512x512/apps
install -m 0644 %{SOURCE2} %{buildroot}/usr/share/icons/hicolor/512x512/apps/minido.png

%files
/opt/minido
/usr/share/applications/minido.desktop
/usr/share/icons/hicolor/512x512/apps/minido.png
