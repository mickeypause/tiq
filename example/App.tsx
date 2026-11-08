import { StatusBar } from 'expo-status-bar';
import { useState } from 'react';
import { Alert, Pressable, ScrollView, StyleSheet, Text, TextInput, useColorScheme, View } from 'react-native';

export default function App() {
  const [count, setCount] = useState(0);
  const dark = useColorScheme() === 'dark';
  const styles = createStyles(dark);
  return (
    <View style={styles.root}>
      <StatusBar style="auto" />
      <ScrollView contentContainerStyle={styles.content} keyboardShouldPersistTaps="handled">
        <Text style={styles.eyebrow}>NATIVE QA SANDBOX</Text>
        <Text style={styles.title}>Keep testing.{'\n'}Report in place.</Text>
        <Text style={styles.body}>This is an ordinary Expo host. The reporter starts from native lifecycle hooks, without an import or provider here.</Text>
        <View style={styles.card}>
          <Text style={styles.heading}>Host interaction check</Text>
          <Text style={styles.body}>The floating button should leave the rest of this screen touchable.</Text>
          <Pressable accessibilityLabel="Increment host counter" style={styles.button} onPress={() => setCount(count + 1)}>
            <Text style={styles.buttonText}>Counter · {count}</Text>
          </Pressable>
          <TextInput accessibilityLabel="Host notes" placeholder="Try the host keyboard…" placeholderTextColor={dark ? '#92939d' : '#686974'} style={styles.input} />
          <Pressable style={styles.secondary} onPress={() => Alert.alert('Host dialog', 'The reporter must coexist with native dialogs.')}>
            <Text style={styles.link}>Open native dialog</Text>
          </Pressable>
        </View>
        <Text style={styles.footnote}>Tap Report bug to open the SwiftUI / Compose composer. Connect Linear to submit issues with evidence.</Text>
      </ScrollView>
    </View>
  );
}

const createStyles = (dark: boolean) => StyleSheet.create({
  root: { flex: 1, backgroundColor: dark ? '#101113' : '#f7f7fa' },
  content: { padding: 28, paddingTop: 100, paddingBottom: 140, gap: 24 },
  eyebrow: { color: dark ? '#c2a8ff' : '#6240a3', fontSize: 12, fontWeight: '700', letterSpacing: 2 },
  title: { color: dark ? '#f4f4f5' : '#18191d', fontSize: 40, fontWeight: '700', letterSpacing: -1.5 },
  body: { color: dark ? '#b0b0b9' : '#555661', fontSize: 16, lineHeight: 25 },
  card: { backgroundColor: dark ? '#1b1c20' : '#ffffff', padding: 24, borderRadius: 24, gap: 18 },
  heading: { color: dark ? '#f4f4f5' : '#18191d', fontSize: 20, fontWeight: '600' },
  button: { backgroundColor: '#c2a8ff', borderRadius: 14, padding: 16, alignItems: 'center' },
  buttonText: { color: '#201534', fontSize: 17, fontWeight: '600' },
  input: { borderWidth: 1, borderColor: dark ? '#3c3d45' : '#c9cad3', borderRadius: 12, padding: 16, color: dark ? '#f4f4f5' : '#18191d', fontSize: 16 },
  secondary: { paddingVertical: 8 },
  link: { color: dark ? '#c2a8ff' : '#6240a3', fontSize: 16 },
  footnote: { color: dark ? '#92939d' : '#686974', fontSize: 14, lineHeight: 22 },
});
